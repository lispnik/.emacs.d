;; -*- lexical-binding: t; -*-
(setq package-enable-at-startup nil)
(setq gc-cons-threshold 100000000)
(setq read-process-output-max 1000000)
(setq inhibit-startup-screen t)
(when (boundp 'tool-bar-mode) (tool-bar-mode -1))
(when (member window-system '(ns)) (set-background-color "#191D27"))
