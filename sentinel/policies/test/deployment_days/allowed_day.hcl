mock "time" {
  data = {
    now = {
      weekday  = "monday"
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
