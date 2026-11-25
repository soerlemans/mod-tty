# Example config:

(defn clock-cb [exit-code]
  (def d (os/date (os/time) true))
  (string/format "%02d:%02d:%02d" (d :hours) (d :minutes) (d :seconds)))


# Set font size.
(set-font-size 15)

# Modeline configuration.
(register-modeline-cb 10 (fn [exit-code]
													 (string "Hello from modeline")))

(register-modeline-cb 20 (fn [exit-code]
													 (string "[" exit-code "]")))

(register-modeline-cb 50 clock-cb)
