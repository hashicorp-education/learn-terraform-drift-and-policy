mock "time" {
  data = {
    now = {
      weekday_name  = "Tuesday"
    }
  }
}

param "forbidden_days" {
  value = ["Friday"]
}

test {
    rules = {
        main = true
    }
}
