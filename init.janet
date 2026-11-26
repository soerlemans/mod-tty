# Example config:

(defn clock-cb [exit-code]
  (def d (os/date (os/time) true))
  (string/format "%02d:%02d:%02d" (d :hours) (d :minutes) (d :seconds)))


(var cached-weather "")
(var last-fetch 0)
(defn weather-cb [exit-code]
  (def now (os/time))
  (when (> (- now last-fetch) 600)
    (set last-fetch now)
    (def buf @"")
    (def proc (os/spawn ["sh" "-c" "curl -fsSL --max-time 2 'https://wttr.in/?format=3'"]
                        :p {:out buf :err :pipe}))
    (when (= (:wait proc) 0)
      (set cached-weather (string/trim (string buf)))))
  cached-weather)


# Set font size.
(set-font-size 15)

# Modeline configuration.
(register-modeline-cb 20 (fn [exit-code]
													 (string "Hello from modeline")))

(register-modeline-cb 20 (fn [exit-code]
													 (string "[" exit-code "]")))

(register-modeline-cb 100 clock-cb)
# (register-modeline-cb 40 weather-cb)
