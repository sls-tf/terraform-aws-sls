# EventBridge & Schedule Event Parsing Tests
# Tests for event flattening logic (Roadmap #7)

# Test: Schedule event with rate expression (string syntax)
run "schedule_rate_string_syntax" {
  command = plan

  variables {
    config_path = "tests/fixtures/schedule-rate-simple.yml"
  }

  # Verify schedule event parsed
  assert {
    condition     = length(local.all_schedule_events) == 1
    error_message = "Should parse 1 schedule event from simple rate syntax"
  }

  assert {
    condition     = local.schedule_event_map["cronJob-schedule-0"].schedule_expression == "rate(5 minutes)"
    error_message = "Schedule expression should match rate"
  }

  assert {
    condition     = local.schedule_event_map["cronJob-schedule-0"].enabled == true
    error_message = "Schedule should be enabled by default"
  }
}

# Test: Schedule event with cron expression (object syntax)
run "schedule_cron_object_syntax" {
  command = plan

  variables {
    config_path = "tests/fixtures/schedule-cron-object.yml"
  }

  # Verify schedule event parsed with object syntax
  assert {
    condition     = length(local.all_schedule_events) == 1
    error_message = "Should parse 1 schedule event from object syntax"
  }

  assert {
    condition     = local.schedule_event_map["dailyReport-schedule-0"].schedule_expression == "cron(0 12 * * ? *)"
    error_message = "Schedule expression should match cron"
  }

  assert {
    condition     = local.schedule_event_map["dailyReport-schedule-0"].enabled == false
    error_message = "Schedule should respect enabled: false"
  }

  assert {
    condition     = local.schedule_event_map["dailyReport-schedule-0"].description == "Daily report generation at noon UTC"
    error_message = "Description should be parsed"
  }
}

# Test: EventBridge event with pattern
run "eventbridge_with_pattern" {
  command = plan

  variables {
    config_path = "tests/fixtures/eventbridge-pattern.yml"
  }

  # Verify eventBridge event parsed
  assert {
    condition     = length(local.all_eventbridge_events) == 1
    error_message = "Should parse 1 eventBridge event"
  }

  assert {
    condition     = local.eventbridge_event_map["ec2Handler-eventbridge-0"].eventBus == "default"
    error_message = "Event bus should default to 'default'"
  }

  assert {
    condition     = local.eventbridge_event_map["ec2Handler-eventbridge-0"].enabled == true
    error_message = "EventBridge should be enabled by default"
  }
}

# Test: EventBridge with custom event bus
run "eventbridge_custom_bus" {
  command = plan

  variables {
    config_path = "tests/fixtures/eventbridge-custom-bus.yml"
  }

  # Verify custom event bus
  assert {
    condition     = local.eventbridge_event_map["customHandler-eventbridge-0"].eventBus == "custom-event-bus"
    error_message = "Event bus should match custom value"
  }

  assert {
    condition     = local.eventbridge_event_map["customHandler-eventbridge-0"].description == "Custom event bus handler"
    error_message = "Description should be parsed"
  }
}

# Test: Multiple events per function
run "multiple_events_per_function" {
  command = plan

  variables {
    config_path = "tests/fixtures/schedule-multiple-events.yml"
  }

  # Verify multiple schedule events
  assert {
    condition     = length(local.all_schedule_events) == 2
    error_message = "Should parse 2 schedule events"
  }

  # Verify eventBridge event
  assert {
    condition     = length(local.all_eventbridge_events) == 1
    error_message = "Should parse 1 eventBridge event"
  }

  # Verify unique event keys
  assert {
    condition     = can(local.schedule_event_map["multiSchedule-schedule-0"])
    error_message = "First schedule event should have key with index 0"
  }

  assert {
    condition     = can(local.schedule_event_map["multiSchedule-schedule-1"])
    error_message = "Second schedule event should have key with index 1"
  }

  assert {
    condition     = can(local.eventbridge_event_map["multiSchedule-eventbridge-2"])
    error_message = "EventBridge event should have key with index 2"
  }
}

# Test: Function without events returns empty maps
run "no_events_empty_maps" {
  command = plan

  variables {
    config_path = "tests/fixtures/http-full-example.yml"
  }

  # Verify no schedule or eventBridge events (http-full-example only has HTTP events)
  assert {
    condition     = length(local.all_schedule_events) == 0
    error_message = "Should have 0 schedule events for HTTP-only functions"
  }

  assert {
    condition     = length(local.all_eventbridge_events) == 0
    error_message = "Should have 0 eventBridge events for HTTP-only functions"
  }
}
