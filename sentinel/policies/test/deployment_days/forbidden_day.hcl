mock "time" {
  data = {
    now = {
      weekday_name  = "Friday"
    }
  }
}

param "forbidden_days" {
  value = ["Friday"]
}

test {
    rules = {
        main = false
    }
}
