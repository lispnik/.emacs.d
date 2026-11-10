;;; objc-tools.el --- Documentation lookup for Objective-C selectors -*- lexical-binding: t; -*-

;; Author: Matthew Kennedy
;; Keywords: objc, c, docs, convenience
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; Look up the Objective-C selector at point -- "webView:didFinishNavigation:",
;; "URLWithString:", "title" -- and read Apple's documentation for it inside
;; Emacs.
;;
;; The documentation comes from a local SQLite database built by
;; ~/.emacs.d/objc-docs/build.py, which crawls the same DocC JSON that
;; developer.apple.com and Dash's Apple API Reference docset are both built
;; from.  The index -- every Objective-C symbol Apple documents, with its
;; owning class, framework and one-line abstract -- is local and answers in
;; milliseconds.  Full pages are fetched once, on first view, and cached in the
;; same database, so a selector you have read before needs no network at all.
;;
;; Build the index before first use (about five minutes):
;;
;;     python3 ~/.emacs.d/objc-docs/build.py index
;;     python3 ~/.emacs.d/objc-docs/build.py abstracts
;;
;; and, for a framework you use constantly, cache every page up front:
;;
;;     python3 ~/.emacs.d/objc-docs/build.py prefetch WebKit
;;
;; Selectors are recognized in three positions, so this is as useful from Lisp
;; FFI code (where selectors are strings) as from Objective-C itself:
;;
;;   1. Inside a string literal -- (objc:invoke view "loadRequest:" req)
;;   2. Inside a message send   -- [view loadRequest:req]
;;   3. As a bare token         -- webView:didFinishNavigation:
;;
;; Usage:
;;
;;   (add-to-list 'load-path (expand-file-name "site-lisp" user-emacs-directory))
;;   (require 'objc-tools)
;;   (global-set-key (kbd "C-c o") #'objc-tools-lookup-selector)
;;
;; `C-u M-x objc-tools-lookup-selector' always prompts, with the selector at
;; point as the default.  When several classes declare the selector, you pick
;; one by completion.  `M-x objc-tools-search' runs a full-text search over
;; every abstract in the index.  In a documentation buffer: `w' opens the page
;; on developer.apple.com, `d' opens it in Dash, `h' shows the SDK header
;; declaration, `l' returns to the list of matches, `g' re-fetches, `q' quits.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'url-util)

(defgroup objc-tools nil
  "Documentation lookup for Objective-C selectors."
  :group 'tools
  :prefix "objc-tools-")

;;;; Customization -- the documentation database

(defcustom objc-tools-db (locate-user-emacs-file "objc-docs/apple-objc.sqlite")
  "SQLite database holding the Objective-C documentation index.
Built by `objc-tools-build-script'."
  :type 'file)

(defcustom objc-tools-build-script (locate-user-emacs-file "objc-docs/build.py")
  "Script that builds the index and fetches pages from Apple."
  :type 'file)

(defcustom objc-tools-python "python3"
  "Python interpreter used to run `objc-tools-build-script'."
  :type 'string)

(defcustom objc-tools-fetch-pages t
  "When non-nil, fetch a symbol's page from Apple the first time it is read.
The page is stored in the database, so it is fetched only once.  With this
nil, lookups stay entirely offline and show only what the index holds."
  :type 'boolean)

(defcustom objc-tools-max-results 100
  "Maximum number of entries returned by a full-text search."
  :type 'integer)

;;;; Customization -- rendering

(defcustom objc-tools-render-width nil
  "Width to fill documentation to, or nil to use the window width."
  :type '(choice (const :tag "Window width" nil) integer))

;;;; Customization -- Dash

(defcustom objc-tools-dash-search-keys "apple"
  "Dash search keyword used by `objc-tools-open-in-dash'.
This is the docset keyword shown in Dash's preferences, without the colon."
  :type 'string)

;;;; Customization -- SDK headers

(defcustom objc-tools-sdk-path nil
  "Path to the macOS SDK whose headers `objc-tools-show-headers' searches.
When nil, ask `xcrun --show-sdk-path' and cache the answer."
  :type '(choice (const :tag "Detect with xcrun" nil) directory))

(defcustom objc-tools-extra-header-roots nil
  "Additional directories searched for headers, alongside the SDK frameworks."
  :type '(repeat directory))

(defcustom objc-tools-include-private-frameworks nil
  "When non-nil, also search the SDK's PrivateFrameworks directory."
  :type 'boolean)

(defcustom objc-tools-grep-program "grep"
  "Program used to scan headers.  Must accept -R, -E, -n and --include."
  :type 'string)

(defcustom objc-tools-doc-lookback 14
  "How many lines to search backwards for the start of a declaration."
  :type 'integer)

(defcustom objc-tools-online-url-format
  "https://developer.apple.com/search/?q=%s&type=Documentation"
  "Format string for the online documentation search URL.
%s is replaced with the URL-encoded selector.  Used only when the exact page
URL is unknown."
  :type 'string)

(define-error 'objc-tools-no-database
  "The Objective-C documentation index has not been built")

(defvar objc-tools--db-connection nil
  "Open connection to `objc-tools-db', or nil.")

(defvar objc-tools--sdk-path-cache nil)
(defvar objc-tools--header-cache (make-hash-table :test #'equal))

;;;; Reading a selector out of the buffer

(defconst objc-tools--selector-re
  "\\`[A-Za-z_][A-Za-z0-9_]*\\(:\\([A-Za-z_][A-Za-z0-9_]*:\\)*\\)?\\'"
  "A well-formed selector: a bare name, or colon-terminated keyword parts.")

(defun objc-tools-valid-selector-p (selector)
  "Return non-nil when SELECTOR looks like an Objective-C selector."
  (and (stringp selector)
       (string-match-p objc-tools--selector-re selector)))

(defun objc-tools--normalize (selector)
  "Trim SELECTOR and drop any leading -/+ method marker."
  (when selector
    (let ((s (string-trim selector)))
      (when (string-match "\\`[-+][ \t]*" s)
        (setq s (substring s (match-end 0))))
      (unless (string-empty-p s) s))))

(defun objc-tools--string-at-point ()
  "Return the contents of the string literal surrounding point, if any."
  (ignore-errors
    (let* ((ppss (syntax-ppss))
           (start (and (nth 3 ppss) (nth 8 ppss))))
      (when start
        (save-excursion
          (goto-char start)
          (forward-sexp)
          (buffer-substring-no-properties (1+ start) (1- (point))))))))

(defun objc-tools--strip-nested (text)
  "Remove bracketed, parenthesized and quoted spans from TEXT."
  (let ((out '()) (depth 0) (in-string nil) (i 0) (n (length text)))
    (while (< i n)
      (let ((c (aref text i)))
        (cond
         (in-string
          (cond ((eq c ?\\) (setq i (1+ i)))
                ((eq c ?\") (setq in-string nil))))
         ((eq c ?\") (setq in-string t))
         ((memq c '(?\[ ?\()) (setq depth (1+ depth)))
         ((memq c '(?\] ?\))) (setq depth (max 0 (1- depth))))
         ((zerop depth) (push c out))))
      (setq i (1+ i)))
    (apply #'string (nreverse out))))

(defun objc-tools--message-send-at-point ()
  "Return the selector of the Objective-C message send surrounding point."
  (ignore-errors
    (let* ((ppss (syntax-ppss))
           (opens (nth 9 ppss))
           (open (cl-find-if (lambda (pos) (eq (char-after pos) ?\[))
                             (reverse opens))))
      (when open
        (let* ((close (or (ignore-errors
                            (save-excursion (goto-char open) (forward-sexp) (point)))
                          (line-end-position)))
               (body (objc-tools--strip-nested
                      (buffer-substring-no-properties (1+ open) (1- close))))
               (parts '())
               (start 0))
          (while (string-match "\\([A-Za-z_][A-Za-z0-9_]*\\)[ \t\n]*:" body start)
            (push (match-string 1 body) parts)
            (setq start (match-end 0)))
          (when parts
            (concat (mapconcat #'identity (nreverse parts) ":") ":")))))))

(defun objc-tools--token-at-point ()
  "Return the selector-shaped token around point."
  (save-excursion
    (let ((chars "A-Za-z0-9_:"))
      (skip-chars-backward chars)
      (let ((beg (point)))
        (skip-chars-forward chars)
        (unless (= beg (point))
          (buffer-substring-no-properties beg (point)))))))

;;;###autoload
(defun objc-tools-selector-at-point ()
  "Return the Objective-C selector at point, or nil.
Looks first at an active region, then at an enclosing string literal, then at
an enclosing message send, and finally at the token around point."
  (objc-tools--normalize
   (cl-some (lambda (candidate)
              (let ((s (objc-tools--normalize candidate)))
                (and (objc-tools-valid-selector-p s) s)))
            (list (when (use-region-p)
                    (buffer-substring-no-properties (region-beginning) (region-end)))
                  (objc-tools--string-at-point)
                  (objc-tools--message-send-at-point)
                  (objc-tools--token-at-point)))))

;;;; The local documentation database

(defun objc-tools--db ()
  "Return the open connection to the documentation database.
Signals `objc-tools-no-database' when it has not been built yet."
  (unless (and objc-tools--db-connection (sqlitep objc-tools--db-connection))
    (let ((file (expand-file-name objc-tools-db)))
      (unless (file-readable-p file)
        (signal 'objc-tools-no-database
                (list (format "%s does not exist; run `python3 %s index'"
                              file objc-tools-build-script))))
      (setq objc-tools--db-connection (sqlite-open file))))
  objc-tools--db-connection)

(defun objc-tools--query (sql &optional args)
  "Run SQL with ARGS against the documentation database."
  (sqlite-select (objc-tools--db) sql args))

(defun objc-tools--symbol-row (row)
  "Convert a `symbol' table ROW into a plist."
  (pcase-let ((`(,name ,marker ,kind ,owner ,framework ,path ,abstract) row))
    (list :name name :marker marker :kind kind :owner owner
          :framework framework :path path :abstract abstract)))

(defconst objc-tools--symbol-columns
  "name, marker, kind, owner, framework, path, abstract")

(defun objc-tools-symbols (selector)
  "Return every documented symbol named exactly SELECTOR.
Methods come first, then properties, then everything else; within a kind the
order is by framework and owning class."
  (mapcar #'objc-tools--symbol-row
          (objc-tools--query
           (concat "SELECT " objc-tools--symbol-columns " FROM symbol"
                   " WHERE name = ?"
                   " ORDER BY CASE kind WHEN 'method' THEN 0"
                   "                    WHEN 'property' THEN 1 ELSE 2 END,"
                   "          framework, owner")
           (list selector))))

(defun objc-tools--quote-fts (query)
  "Return QUERY with every word quoted as an FTS5 string.
FTS5 reads bare punctuation as syntax -- a colon introduces a column filter,
so the selector \"webView:didFinish:\" would be read as a column named
webView -- and quoting turns the whole thing back into words to match."
  (mapconcat
   (lambda (token)
     (let* ((prefix (string-suffix-p "*" token))
            (word (if prefix (substring token 0 -1) token)))
       (concat "\"" (string-replace "\"" "\"\"" word) "\"" (if prefix "*" ""))))
   (split-string query "[ \t]+" t)
   " "))

(defconst objc-tools--fts-syntax-re
  "[\"()^]\\|\\(\\`\\|[ \t(]\\)\\(AND\\|OR\\|NOT\\|NEAR\\)\\([ \t(]\\|\\\'\\)"
  "What a query must contain to be passed to FTS5 as written.")

(defun objc-tools-search-index (query &optional limit)
  "Return symbols matching QUERY, best match first.
Ordinary text is quoted word by word before it reaches FTS5, so punctuation
in a selector is matched rather than read as syntax; a query that already
uses FTS5 syntax -- quotes, parentheses, or AND/OR/NOT/NEAR -- is passed
through untouched, and retried quoted if FTS5 rejects it."
  (let ((explicit (string-match-p objc-tools--fts-syntax-re query)))
    (condition-case nil
        (objc-tools--search-index-1
         (if explicit query (objc-tools--quote-fts query)) limit)
      (error (objc-tools--search-index-1 (objc-tools--quote-fts query) limit)))))

(defun objc-tools--search-index-1 (query &optional limit)
  "Run one FTS5 QUERY, returning at most LIMIT symbols."
  (mapcar #'objc-tools--symbol-row
          (objc-tools--query
           (concat "SELECT " (mapconcat (lambda (c) (concat "s." (string-trim c)))
                                        (split-string objc-tools--symbol-columns ",")
                                        ", ")
                   " FROM symbol_fts f JOIN symbol s ON s.id = f.rowid"
                   " WHERE symbol_fts MATCH ? ORDER BY rank LIMIT ?")
           (list query (or limit objc-tools-max-results)))))

(defun objc-tools--stored-page (path)
  "Return the cached page for PATH as a plist, or nil."
  (when-let* ((row (car (objc-tools--query
                         (concat "SELECT title, role, platforms, abstract,"
                                 " declaration, parameters, discussion, url"
                                 " FROM page WHERE path = ?")
                         (list path)))))
    (pcase-let ((`(,title ,role ,platforms ,abstract ,declaration
                          ,parameters ,discussion ,url) row))
      (list :title title :role role :platforms platforms :abstract abstract
            :declaration declaration :parameters parameters
            :discussion discussion :url url))))

(defun objc-tools--fetch-page (path)
  "Fetch the page for PATH from Apple and store it in the database.
Returns the stored page, or nil when the fetch failed."
  (let ((script (expand-file-name objc-tools-build-script)))
    (unless (file-readable-p script)
      (user-error "Cannot find %s" script))
    ;; The builder owns the DocC parsing, including the JSON-patch dance that
    ;; turns a Swift-first page into its Objective-C variant, so fetching goes
    ;; through it rather than being written twice.
    (with-temp-buffer
      (let ((status (call-process objc-tools-python nil t nil
                                  script "--db" (expand-file-name objc-tools-db)
                                  "page" path)))
        (unless (eq status 0)
          (message "objc-tools: could not fetch %s (%s)" path
                   (string-trim (buffer-string))))))
    ;; The page was written by a separate process; reopen so this connection
    ;; sees it.
    (objc-tools-close)
    (objc-tools--stored-page path)))

(defun objc-tools-page (path &optional force)
  "Return the documentation page for PATH, fetching it when necessary."
  (or (and (not force) (objc-tools--stored-page path))
      (and objc-tools-fetch-pages (objc-tools--fetch-page path))))

(defun objc-tools-close ()
  "Close the database connection, if one is open."
  (when (and objc-tools--db-connection (sqlitep objc-tools--db-connection))
    (sqlite-close objc-tools--db-connection))
  (setq objc-tools--db-connection nil))

;;;###autoload
(defun objc-tools-clear-cache ()
  "Close the database and forget the cached SDK path and header searches."
  (interactive)
  (objc-tools-close)
  (clrhash objc-tools--header-cache)
  (setq objc-tools--sdk-path-cache nil)
  (message "objc-tools: caches cleared"))

;;;; Documentation buffers

(defvar-local objc-tools--selector nil
  "The selector this buffer documents.")
(defvar-local objc-tools--entry nil
  "The symbol plist this buffer documents.")
(defvar-local objc-tools--online-url nil
  "The developer.apple.com URL for this buffer's entry, if known.")

(defvar objc-tools-doc-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "w") #'objc-tools-browse-selector)
    (define-key map (kbd "d") #'objc-tools-open-in-dash)
    (define-key map (kbd "h") #'objc-tools-show-headers)
    (define-key map (kbd "l") #'objc-tools-other-match)
    (define-key map (kbd "g") #'objc-tools-refresh)
    map)
  "Keymap for `objc-tools-doc-mode'.")

(define-derived-mode objc-tools-doc-mode special-mode "ObjC-Doc"
  "Major mode for Apple's Objective-C documentation."
  (setq-local truncate-lines nil))

(defun objc-tools--insert-heading (text)
  (insert "\n" (propertize text 'face 'font-lock-keyword-face) "\n"))

(defun objc-tools--width ()
  "Return the column to fill documentation to."
  (or objc-tools-render-width
      (when-let* ((window (get-buffer-window (current-buffer) t)))
        (window-body-width window))
      78))

(defun objc-tools--insert-filled (text &optional prefix)
  "Insert TEXT as a filled paragraph, every line under PREFIX."
  (let ((start (point))
        (prefix (or prefix "  ")))
    (insert prefix text "\n")
    (let ((fill-prefix prefix)
          (fill-column (max 40 (- (objc-tools--width) 2)))
          (adaptive-fill-mode nil))
      (fill-region start (point)))))

(defun objc-tools--field (plist key)
  "Return KEY of PLIST when it holds a non-blank string.
SQLite hands back empty strings where a page simply has no such section, and
an empty string is as true as any other value in Lisp."
  (let ((value (plist-get plist key)))
    (and (stringp value)
         (not (string-blank-p value))
         value)))

(defun objc-tools--insert-page (entry page)
  "Insert the documentation for ENTRY, using PAGE when it has been fetched."
  (let ((name (or (objc-tools--field page :title) (plist-get entry :name)))
        (role (or (objc-tools--field page :role)
                  (capitalize (or (plist-get entry :kind) ""))))
        (owner (plist-get entry :owner))
        (framework (plist-get entry :framework))
        (abstract (or (objc-tools--field page :abstract)
                      (objc-tools--field entry :abstract))))
    (insert (propertize name 'face 'font-lock-function-name-face))
    (when role
      (insert (propertize (format "   %s" role) 'face 'font-lock-comment-face)))
    (insert "\n")
    (insert (propertize (string-join (delq nil (list owner framework)) "  —  ")
                        'face 'font-lock-type-face)
            "\n")
    (when-let* ((platforms (objc-tools--field page :platforms)))
      (insert (propertize platforms 'face 'font-lock-comment-face) "\n"))
    (when abstract
      (insert "\n")
      (objc-tools--insert-filled abstract ""))
    (when-let* ((declaration (objc-tools--field page :declaration)))
      (objc-tools--insert-heading "Declaration")
      (insert "  " (objc-tools--fontify declaration) "\n"))
    (when-let* ((parameters (objc-tools--field page :parameters)))
      (objc-tools--insert-heading "Parameters")
      (dolist (line (split-string parameters "\n" t))
        (if (string-match "\\`\\([^:]*\\): ?\\(.*\\)\\'" line)
            (progn
              (insert "  " (propertize (match-string 1 line)
                                       'face 'font-lock-variable-name-face)
                      "\n")
              (objc-tools--insert-filled (match-string 2 line) "    "))
          (insert "  " line "\n"))))
    (when-let* ((discussion (objc-tools--field page :discussion)))
      (objc-tools--insert-heading "Discussion")
      (dolist (paragraph (split-string discussion "\n\n" t))
        (objc-tools--insert-filled paragraph "  ")
        (insert "\n")))
    (unless page
      (insert (propertize
               (if objc-tools-fetch-pages
                   "\nThe page could not be fetched; showing the index entry only.\n"
                 "\nPage fetching is off; showing the index entry only.\n")
               'face 'font-lock-warning-face)))
    (insert "\n" (propertize (concat (plist-get entry :path)
                                     "\n\nw online   d Dash   h headers"
                                     "   l other matches   g refetch   q quit")
                             'face 'font-lock-comment-face)
            "\n")))

(defun objc-tools--display-entry (selector entry &optional force)
  "Show the documentation for ENTRY, the chosen match for SELECTOR."
  (let* ((page (objc-tools-page (plist-get entry :path) force))
         (buffer (get-buffer-create
                  (format "*objc-doc: %s*" (or (plist-get entry :name) selector)))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (objc-tools-doc-mode)))
    (let ((window (display-buffer buffer)))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (objc-tools--insert-page entry page)
          (setq objc-tools--selector selector
                objc-tools--entry entry
                objc-tools--online-url
                (or (plist-get page :url)
                    (concat "https://developer.apple.com"
                            (plist-get entry :path) "?language=objc")))
          (goto-char (point-min))))
      (when (window-live-p window)
        (set-window-point window (point-min))
        (set-window-start window (point-min))))
    buffer))

(defun objc-tools--annotation (entry)
  "Return the completion annotation for ENTRY."
  (string-join (delq nil (list (plist-get entry :kind)
                               (plist-get entry :framework)
                               (plist-get entry :abstract)))
               "  "))

(defun objc-tools--choose (selector entries)
  "Return the entry to show for SELECTOR, asking when ENTRIES is ambiguous."
  (if (null (cdr entries))
      (car entries)
    (let ((table (make-hash-table :test #'equal))
          (candidates '()))
      (dolist (entry entries)
        (let* ((base (if (plist-get entry :owner)
                         (format "%s.%s" (plist-get entry :owner) (plist-get entry :name))
                       (plist-get entry :name)))
               (label base)
               (n 2))
          (while (gethash label table)
            (setq label (format "%s<%d>" base n) n (1+ n)))
          (puthash label entry table)
          (push label candidates)))
      (setq candidates (nreverse candidates))
      (let* ((completion-extra-properties
              (list :annotation-function
                    (lambda (label)
                      (when-let* ((entry (gethash label table)))
                        (concat "  " (objc-tools--annotation entry))))))
             (choice (completing-read
                      (format "%s (%d matches): " selector (length entries))
                      (lambda (string predicate action)
                        (if (eq action 'metadata)
                            '(metadata (display-sort-function . identity)
                                       (cycle-sort-function . identity))
                          (complete-with-action action candidates string predicate)))
                      nil t)))
        (gethash choice table)))))

;;;; Commands

(defun objc-tools--read-selector (prompt-p)
  "Return the selector to look up, prompting when PROMPT-P or none is at point."
  (let ((default (objc-tools-selector-at-point)))
    (objc-tools--normalize
     (if (or prompt-p (not default))
         (read-string (if default (format "Selector (default %s): " default) "Selector: ")
                      nil nil default)
       default))))

(defun objc-tools--lookup (selector &optional force)
  "Show documentation for SELECTOR.
With FORCE non-nil, re-fetch the page even when it is already cached."
  (condition-case err
      (let ((entries (objc-tools-symbols selector)))
        (cond
         (entries
          (objc-tools--display-entry selector (objc-tools--choose selector entries)
                                     force))
         (t
          (message "%s is not in the index; searching the SDK headers" selector)
          (objc-tools-show-headers selector))))
    (objc-tools-no-database
     (message "No documentation index (%s); searching the SDK headers" (cadr err))
     (objc-tools-show-headers selector))))

;;;###autoload
(defun objc-tools-lookup-selector (&optional prompt)
  "Show documentation for the Objective-C selector at point.
With a prefix argument PROMPT, always ask for the selector."
  (interactive "P")
  (let ((selector (objc-tools--read-selector prompt)))
    (unless (objc-tools-valid-selector-p selector)
      (user-error "Not an Objective-C selector: %s" (or selector "")))
    (objc-tools--lookup selector)))

;;;###autoload
(defun objc-tools-search (query)
  "Search every documented Objective-C symbol for QUERY.
QUERY is an FTS5 expression, so \"navigation delegate\" finds symbols whose
name, class, framework or abstract mention both words, and \"didFinish*\"
matches by prefix."
  (interactive
   (list (read-string "Search Apple docs: " (objc-tools-selector-at-point))))
  (let ((entries (objc-tools-search-index query)))
    (unless entries
      (user-error "Nothing matches %s" query))
    (objc-tools--display-entry query (objc-tools--choose query entries))))

(defun objc-tools-refresh ()
  "Re-fetch the page shown in this buffer."
  (interactive)
  (unless objc-tools--entry
    (user-error "No entry associated with this buffer"))
  (objc-tools--display-entry objc-tools--selector objc-tools--entry t))

(defun objc-tools-other-match ()
  "Choose another symbol with the same name as the one shown here."
  (interactive)
  (unless objc-tools--selector
    (user-error "No selector associated with this buffer"))
  (let ((entries (objc-tools-symbols objc-tools--selector)))
    (if (cdr entries)
        (objc-tools--display-entry objc-tools--selector
                                   (objc-tools--choose objc-tools--selector entries))
      (message "%s has only one match" objc-tools--selector))))

;;;###autoload
(defun objc-tools-build (step &optional argument)
  "Run STEP of the index builder in a compilation buffer.
STEP is \"index\" to crawl every framework's symbol tree, \"abstracts\" to
fill in one-line summaries, or \"prefetch\" to cache every page of one
framework, named by ARGUMENT."
  (interactive
   (let ((step (completing-read "Build step: "
                                '("index" "abstracts" "prefetch") nil t)))
     (list step
           (when (member step '("abstracts" "prefetch"))
             (read-string (format "Framework%s: "
                                  (if (equal step "abstracts")
                                      " (empty for all)" "")))))))
  (let ((command (string-join
                  (delq nil (list (shell-quote-argument objc-tools-python)
                                  (shell-quote-argument
                                   (expand-file-name objc-tools-build-script))
                                  "--db" (shell-quote-argument
                                          (expand-file-name objc-tools-db))
                                  step
                                  (unless (string-blank-p (or argument ""))
                                    (shell-quote-argument argument))))
                  " ")))
    ;; The builder writes to the database this session may have open.
    (objc-tools-close)
    (compile command)))

;;;###autoload
(defun objc-tools-open-in-dash (&optional selector)
  "Open SELECTOR in Dash itself, restricted to the Objective-C docset."
  (interactive (list (or objc-tools--selector
                         (objc-tools--read-selector current-prefix-arg))))
  (let ((selector (or selector (objc-tools--read-selector nil))))
    (unless (objc-tools-valid-selector-p selector)
      (user-error "Not an Objective-C selector: %s" (or selector "")))
    ;; The colons in a selector are not legal in a URL host, so the whole query
    ;; goes through `url-hexify-string'.
    (call-process "open" nil 0 nil
                  (format "dash-plugin://keys=%s&query=%s"
                          (url-hexify-string objc-tools-dash-search-keys)
                          (url-hexify-string selector)))))

;;;###autoload
(defun objc-tools-browse-selector (&optional selector)
  "Open Apple's online documentation for SELECTOR in a browser.
In a documentation buffer this opens that symbol's own page; elsewhere it
falls back to a documentation search."
  (interactive (list (or objc-tools--selector
                         (objc-tools--read-selector current-prefix-arg))))
  (let ((url (or objc-tools--online-url
                 (format objc-tools-online-url-format
                         (url-hexify-string (or selector ""))))))
    (browse-url url)))

;;;; Fallback: the macOS SDK headers

(defun objc-tools-sdk-path ()
  "Return the SDK path to search, signalling an error if none can be found."
  (or objc-tools-sdk-path
      objc-tools--sdk-path-cache
      (setq objc-tools--sdk-path-cache
            (let ((path (with-temp-buffer
                          (when (zerop (ignore-errors
                                         (call-process "xcrun" nil t nil
                                                       "--show-sdk-path")))
                            (string-trim (buffer-string))))))
              (if (and path (file-directory-p path))
                  path
                (user-error "Cannot locate a macOS SDK; set `objc-tools-sdk-path'"))))))

(defun objc-tools-header-roots ()
  "Return the list of directories to scan for headers."
  (let* ((sdk (objc-tools-sdk-path))
         (roots (list (expand-file-name "System/Library/Frameworks" sdk)
                      (expand-file-name "usr/include/objc" sdk))))
    (when objc-tools-include-private-frameworks
      (push (expand-file-name "System/Library/PrivateFrameworks" sdk) roots))
    (cl-remove-if-not #'file-directory-p
                      (append (nreverse roots)
                              (mapcar #'expand-file-name
                                      objc-tools-extra-header-roots)))))

(defun objc-tools--strip-parens (text)
  "Remove balanced parenthesized groups from TEXT, keeping the rest."
  (let ((out '()) (depth 0))
    (dolist (c (string-to-list text))
      (cond ((eq c ?\() (setq depth (1+ depth)))
            ((eq c ?\)) (setq depth (max 0 (1- depth))))
            ((zerop depth) (push c out))))
    (apply #'string (nreverse out))))

(defun objc-tools--method-selector (decl)
  "Return the selector declared by method declaration DECL, or nil."
  (let ((body (objc-tools--strip-parens decl))
        (parts '())
        (start 0))
    (when (string-match "\\`[ \t\n]*[-+]" body)
      (setq body (substring body (match-end 0))))
    (while (string-match "\\([A-Za-z_][A-Za-z0-9_]*\\)[ \t\n]*:" body start)
      (push (match-string 1 body) parts)
      (setq start (match-end 0)))
    (if parts
        (concat (mapconcat #'identity (nreverse parts) ":") ":")
      (when (string-match "\\`[ \t\n]*\\([A-Za-z_][A-Za-z0-9_]*\\)" body)
        (match-string 1 body)))))

(defun objc-tools--property-attributes (decl)
  "Return the attribute text of @property declaration DECL."
  (if (string-match "@property[ \t\n]*(\\([^)]*\\))" decl)
      (match-string 1 decl)
    ""))

(defun objc-tools--property-selectors (decl)
  "Return the (GETTER . SETTER) selectors declared by @property DECL.
SETTER is nil for a readonly property."
  (let* ((attrs (objc-tools--property-attributes decl))
         (body (objc-tools--strip-parens decl))
         (name (when (string-match "\\([A-Za-z_][A-Za-z0-9_]*\\)[ \t\n]*;" body)
                 (match-string 1 body))))
    (when name
      (cons (if (string-match "getter[ \t]*=[ \t]*\\([A-Za-z_][A-Za-z0-9_]*\\)" attrs)
                (match-string 1 attrs)
              name)
            (cond
             ((string-match-p "\\_<readonly\\_>" attrs) nil)
             ((string-match "setter[ \t]*=[ \t]*\\([A-Za-z_][A-Za-z0-9_]*:\\)" attrs)
              (match-string 1 attrs))
             (t (concat "set" (upcase (substring name 0 1)) (substring name 1) ":")))))))

(defun objc-tools--declaration-bounds ()
  "Return (BEG . END) of the declaration containing point, or nil."
  (save-excursion
    (beginning-of-line)
    (let ((limit (save-excursion
                   (forward-line (- objc-tools-doc-lookback))
                   (point)))
          (beg nil))
      (while (and (not beg) (>= (point) limit))
        (if (looking-at "[ \t]*\\(@property\\|[-+][ \t]*(\\)")
            (setq beg (point))
          (if (bobp) (setq limit (1+ (point))) (forward-line -1))))
      (when beg
        (goto-char beg)
        (let ((end (save-excursion
                     (if (re-search-forward ";" (+ (point) 4000) t)
                         (point)
                       (line-end-position)))))
          (cons beg end))))))

(defun objc-tools--collapse (text)
  "Collapse TEXT to a single line with single spaces."
  (string-trim (replace-regexp-in-string "[ \t\n]+" " " text)))

(defun objc-tools--clean-comment (lines)
  "Strip comment punctuation from LINES and return the text, or nil if empty."
  (let ((text (mapconcat
               (lambda (line)
                 (let ((s line))
                   (setq s (replace-regexp-in-string "\\`[ \t]*/\\*[*!]?" "" s))
                   (setq s (replace-regexp-in-string "\\*/[ \t]*\\'" "" s))
                   (setq s (replace-regexp-in-string "\\`[ \t]*\\(///?[<!]?\\|\\*\\)[ \t]?" "" s))
                   (string-trim-right s)))
               lines "\n")))
    (setq text (string-trim text))
    (unless (string-empty-p text) text)))

(defun objc-tools--doc-comment-before (pos)
  "Return the documentation comment immediately preceding POS, or nil."
  (save-excursion
    (goto-char pos)
    (beginning-of-line)
    (let ((lines '()))
      (if (save-excursion
            (forward-line -1)
            (and (not (bobp))
                 (string-match-p "\\*/[ \t]*\\'"
                                 (buffer-substring-no-properties
                                  (line-beginning-position) (line-end-position)))))
          (let ((end (save-excursion (forward-line -1) (line-end-position))))
            (save-excursion
              (goto-char end)
              (when (re-search-backward "/\\*" nil t)
                (setq lines (split-string
                             (buffer-substring-no-properties (point) end) "\n")))))
        (save-excursion
          (forward-line -1)
          (while (and (not (bobp))
                      (string-match-p "\\`[ \t]*///"
                                      (buffer-substring-no-properties
                                       (line-beginning-position) (line-end-position))))
            (push (buffer-substring-no-properties
                   (line-beginning-position) (line-end-position))
                  lines)
            (forward-line -1))))
      (when lines
        (objc-tools--clean-comment lines)))))

(defun objc-tools--owner-at-point ()
  "Return the enclosing @interface or @protocol name, or nil."
  (save-excursion
    (when (re-search-backward
           "^@\\(interface\\|protocol\\|implementation\\|end\\)\\_>" nil t)
      (unless (string= (match-string 1) "end")
        (let ((kind (match-string 1)))
          (when (looking-at
                 "^@[a-z]+[ \t]+\\([A-Za-z_][A-Za-z0-9_]*\\)[ \t]*\\((\\([A-Za-z_][A-Za-z0-9_]*\\))\\)?")
            (list :kind kind
                  :name (match-string 1)
                  :category (match-string 3))))))))

(defun objc-tools--framework-of (file)
  "Return the framework name FILE belongs to, or nil."
  (when (string-match "/\\([^/]+\\)\\.framework/" file)
    (match-string 1 file)))

(defun objc-tools--grep-patterns (selector)
  "Return the extended regexps that find candidate lines for SELECTOR."
  (let ((patterns '()))
    (if (string-suffix-p ":" selector)
        (let ((last (car (last (split-string selector ":" t)))))
          (push (concat last ":") patterns)
          ;; A setter may be declared as a @property instead of a method.
          (when (string-match "\\`set\\([A-Z][A-Za-z0-9_]*\\):\\'" selector)
            (let ((name (let ((n (match-string 1 selector)))
                          (concat (downcase (substring n 0 1)) (substring n 1)))))
              (push (format "@property.*[^A-Za-z0-9_]%s[ \t]*;" name) patterns))))
      (push (format "(^[[:space:]]*[-+][[:space:]]*\\(|@property).*[^A-Za-z0-9_]%s[^A-Za-z0-9_]"
                    selector)
            patterns))
    (nreverse patterns)))

(defun objc-tools--grep (pattern)
  "Run grep for PATTERN over the header roots; return an alist of (FILE . LINES)."
  (let ((roots (objc-tools-header-roots))
        (hits (make-hash-table :test #'equal)))
    (with-temp-buffer
      (apply #'call-process objc-tools-grep-program nil t nil
             (append (list "-R" "-E" "-n" "-I" "--include=*.h" "-e" pattern) roots))
      (goto-char (point-min))
      (while (re-search-forward "^\\(/[^\0\n]*?\\):\\([0-9]+\\):" nil t)
        (let ((file (match-string 1))
              (line (string-to-number (match-string 2))))
          ;; Framework headers are reachable by three symlinked paths; keep one.
          (unless (string-match-p "/Versions/" file)
            (cl-pushnew line (gethash file hits) :test #'=)))
        (forward-line 1)))
    (let ((result '()))
      (maphash (lambda (file lines) (push (cons file (sort lines #'<)) result)) hits)
      result)))

(defun objc-tools--matches-in-file (file lines selector)
  "Return the declarations of SELECTOR among LINES of FILE."
  (let ((found '()))
    (with-temp-buffer
      (insert-file-contents file)
      (dolist (line lines)
        (goto-char (point-min))
        (forward-line (1- line))
        (when-let* ((bounds (objc-tools--declaration-bounds))
                    (raw (buffer-substring-no-properties (car bounds) (cdr bounds)))
                    (decl (objc-tools--collapse raw)))
          (let* ((property (string-prefix-p "@property" decl))
                 (accessors (and property (objc-tools--property-selectors decl)))
                 (kind (cond ((not property)
                              (when (equal selector (objc-tools--method-selector decl))
                                'method))
                             ((equal selector (car accessors)) 'getter)
                             ((equal selector (cdr accessors)) 'setter))))
            (when kind
              (goto-char (car bounds))
              (push (list :file file
                          :line (line-number-at-pos)
                          :kind kind
                          :decl decl
                          :owner (objc-tools--owner-at-point)
                          :doc (objc-tools--doc-comment-before (car bounds))
                          :framework (objc-tools--framework-of file))
                    found))))))
    found))

(defun objc-tools--sort-headers (matches)
  "Sort MATCHES by framework, then file, then line."
  (sort matches
        (lambda (a b)
          (let ((fa (or (plist-get a :framework) ""))
                (fb (or (plist-get b :framework) "")))
            (if (string= fa fb)
                (let ((na (plist-get a :file)) (nb (plist-get b :file)))
                  (if (string= na nb)
                      (< (plist-get a :line) (plist-get b :line))
                    (string< na nb)))
              (string< fa fb))))))

(defun objc-tools-search-headers (selector &optional force)
  "Return the declarations of SELECTOR found in the SDK headers.
With FORCE non-nil, bypass the cache."
  (let ((key (list selector (objc-tools-sdk-path) objc-tools-extra-header-roots
                   objc-tools-include-private-frameworks)))
    (or (and (not force) (gethash key objc-tools--header-cache))
        (puthash key
                 (let ((matches '()))
                   (dolist (pattern (objc-tools--grep-patterns selector))
                     (pcase-dolist (`(,file . ,lines) (objc-tools--grep pattern))
                       (setq matches
                             (append matches
                                     (objc-tools--matches-in-file file lines selector)))))
                   (objc-tools--sort-headers
                    (cl-delete-duplicates
                     matches
                     :test (lambda (a b)
                             (and (equal (plist-get a :file) (plist-get b :file))
                                  (= (plist-get a :line) (plist-get b :line)))))))
                 objc-tools--header-cache))))

(defun objc-tools--fontify (code)
  "Return CODE fontified as Objective-C, if that mode is available."
  (if (fboundp 'objc-mode)
      (with-temp-buffer
        (delay-mode-hooks (objc-mode))
        (insert code)
        (font-lock-ensure)
        (buffer-string))
    code))

(defun objc-tools--owner-string (owner)
  "Return a readable name for OWNER, the plist from `objc-tools--owner-at-point'."
  (if owner
      (concat (plist-get owner :name)
              (when-let* ((cat (plist-get owner :category))) (format " (%s)" cat))
              (when (equal (plist-get owner :kind) "protocol") " <protocol>"))
    "(file scope)"))

(defun objc-tools--visit (file line)
  "Visit FILE at LINE in another window."
  (let ((buffer (find-file-noselect file)))
    (with-current-buffer buffer
      (goto-char (point-min))
      (forward-line (1- line)))
    (pop-to-buffer buffer)
    (recenter)))

(defun objc-tools--insert-header-match (match)
  "Insert one header MATCH into the current buffer."
  (let* ((file (plist-get match :file))
         (line (plist-get match :line))
         (kind (plist-get match :kind))
         (framework (plist-get match :framework)))
    (insert (propertize (objc-tools--owner-string (plist-get match :owner))
                        'face 'font-lock-type-face))
    (when framework
      (insert (propertize (format "  [%s]" framework) 'face 'font-lock-comment-face)))
    (when (memq kind '(getter setter))
      (insert (propertize (format "  (property %s)" kind) 'face 'font-lock-comment-face)))
    (insert "\n  " (objc-tools--fontify (plist-get match :decl)) "\n  ")
    (insert-text-button
     (format "%s:%d" (file-name-nondirectory file) line)
     'action (lambda (_) (objc-tools--visit file line))
     'follow-link t
     'help-echo (format "Visit %s:%d" file line))
    (insert "\n")
    (when-let* ((doc (plist-get match :doc)))
      (dolist (doc-line (split-string doc "\n"))
        (insert (propertize (concat "  " doc-line "\n") 'face 'font-lock-doc-face))))
    (insert "\n")))

(defvar objc-tools-headers-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'push-button)
    (define-key map (kbd "n") #'forward-button)
    (define-key map (kbd "p") #'backward-button)
    (define-key map (kbd "d") #'objc-tools-open-in-dash)
    (define-key map (kbd "w") #'objc-tools-browse-selector)
    map)
  "Keymap for `objc-tools-headers-mode'.")

(define-derived-mode objc-tools-headers-mode special-mode "ObjC-Headers"
  "Major mode for Objective-C declarations found in the SDK headers."
  (setq-local truncate-lines nil))

;;;###autoload
(defun objc-tools-show-headers (&optional selector)
  "Show the SDK header declarations of SELECTOR.
This is the fallback when Dash is unavailable, and is also useful on its own:
it shows the declaration and its header comment for every class that declares
the selector."
  (interactive (list (or objc-tools--selector
                         (objc-tools--read-selector current-prefix-arg))))
  (let* ((selector (or selector (objc-tools--read-selector nil)))
         (matches (objc-tools-search-headers selector)))
    (if (null matches)
        (message "No declaration of %s in %s"
                 selector (file-name-nondirectory (objc-tools-sdk-path)))
      (let ((buffer (get-buffer-create (format "*objc-headers: %s*" selector))))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (objc-tools-headers-mode)
            (setq objc-tools--selector selector)
            (insert (propertize selector 'face 'font-lock-function-name-face) "\n")
            (insert (propertize
                     (format "%d declaration%s in %s\n\n"
                             (length matches)
                             (if (= 1 (length matches)) "" "s")
                             (file-name-nondirectory (objc-tools-sdk-path)))
                     'face 'font-lock-comment-face))
            (mapc #'objc-tools--insert-header-match matches)
            (insert (propertize "RET visit  d Dash  w online  q quit"
                                'face 'font-lock-comment-face))
            (goto-char (point-min))))
        (display-buffer buffer)
        buffer))))

(provide 'objc-tools)

;;; objc-tools.el ends here
