# Default config:

# Defaults:
(set-font-size 15)
(register-modeline-cb 10 (fn [exit-code]
													 (string "Hello from modeline")))

(register-modeline-cb 20 (fn [exit-code]
													 (string "[" exit-code "]")))
