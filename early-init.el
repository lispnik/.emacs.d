;; -*- lexical-binding: t; -*-
;;; Loaded before package initialization and before the first frame is drawn.

;; straight.el manages packages; keep package.el from doing any startup work.
(setq package-enable-at-startup nil)

;; Defer garbage collection during startup for a faster launch, then restore a
;; working threshold once Emacs is up (owned here, not in init.el, so it isn't
;; lowered again partway through startup).
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 100 1024 1024)
                  gc-cons-percentage 0.1)))

;; Larger reads from subprocesses (LSP throughput); set before any server
;; connects. Owned here so init.el doesn't need to repeat it.
(setq read-process-output-max (* 1024 1024))

;; Startup / frame chrome.
(setq inhibit-startup-screen t
      frame-inhibit-implied-resize t)
(when (boundp 'tool-bar-mode) (tool-bar-mode -1))
;; Create GUI frames without a tool bar / scroll bars instead of drawing then
;; removing them (ignored on TTY frames).
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars . nil) default-frame-alist)
(when (member window-system '(ns)) (set-background-color "#191D27"))

;; Native compilation: this Emacs 30.2 can't build subr trampolines (emutls_w
;; link failure), so disable them; keep async-comp warnings out of the way.
;; Drop the trampoline line if a future Emacs build fixes the linker issue.
(setq native-comp-enable-subr-trampolines nil
      native-comp-async-report-warnings-errors 'silent)
