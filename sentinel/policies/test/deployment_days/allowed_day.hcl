mock "time" {
  data = {
    now = {
      weekday_name  = "monday"
    }
  }
}

param "forbidden_days" {
  value = ["friday"]
}

test {
    rules = {
        main = true
    }
}
