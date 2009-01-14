;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ECB
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; load ECB
(require 'ecb)

;; Disable update version check
(setq ecb-version-check nil)

;; Filter unwanted source file
(setq ecb-source-file-regexps (quote ((".*" ("\\(^\\(\\.\\|#\\)\\|\\(~$\\|\\.\\(pyc\\|elc\\|obj\\|o\\|class\\|lib\\|dll\\|a\\|so\\|cache\\)$\\)\\)") ("^\\.\\(emacs\\|gnus\\)$")))))


;;Turn off Tip of the day
(setq ecb-tip-of-the-day nil)

;; Set the layout
(setq ecb-layout-name "left14")

;; Show the source file under the directories
(setq ecb-show-sources-in-directories-buffer '("left7" "left13" "left14" "left15"))

;; Set the left-click mouse button to collapse directory in directory buffer
(setq ecb-primary-secondary-mouse-buttons (quote mouse-1--C-mouse-1))

;; Turn on semantic
(setq semantic-load-turn-everything-on t)
(require 'semantic-load)
