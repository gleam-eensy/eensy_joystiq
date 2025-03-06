import actors/ui
import eensy.{Up, get_system_platform}

import gleam/option.{None, Some}
import gleam/result

import eensy/gpio.{type Level, High, Low}
import eensy/store
import gleam/erlang/process

import gleam/list

// Model -----------------------------------------------------------------------

pub type Model {
  Model(
    led: Level,
    up: Level,
    down: Level,
    left: Level,
    right: Level,
    middle: Level,
  )
}

// Start -----------------------------------------------------------------------

pub fn start() -> Nil {
  let _ = do_start()
  // let _ = process.start(displays_loop, False)
  process.sleep_forever()
}

fn do_start() {
  let default_model =
    Model(led: Low, up: Low, down: Low, left: Low, right: Low, middle: Low)

  use store <- result.try(store.start(default_model))

  // Input actors
  [
    #(12, fn(model, level) { Model(..model, up: level) }),
    #(14, fn(model, level) { Model(..model, down: level) }),
    #(27, fn(model, level) { Model(..model, left: level) }),
    #(26, fn(model, level) { Model(..model, right: level) }),
    #(25, fn(model, level) { Model(..model, middle: level) }),
  ]
  |> list.map(fn(input_definition) {
    setup_input(
      port: input_definition.0,
      transformation: input_definition.1,
      default_model:,
      store:,
      // gpio_led:,
    )
  })

  // Internal Led actor
  use gpio_led <- result.try(
    gpio.start(gpio.pin(
      level: Low,
      pull: Up,
      port: internal_blink_pin(),
      direction: gpio.Output,
      update: None,
    )),
  )

  process.start(fn() { sync_internal_led(store:, gpio_led:) }, False)

  // Display actor

  use display_ui <- result.try(ui.start(address: 60, sda: 21, scl: 18))

  process.start(fn() { sync_display(store:, display_ui:) }, False)

  Ok(Nil)
}

fn setup_input(
  port port: Int,
  store store: store.StoreActor(Model),
  default_model default_model: Model,
  transformation transformation: fn(Model, Level) -> Model,
) {
  use gpio_input <- result.try(
    gpio.start(gpio.pin(
      level: Low,
      pull: Up,
      port:,
      direction: gpio.Input,
      update: Some(fn(level: Level) {
        let current_store_state =
          transformation(
            store.get(store) |> result.unwrap(default_model),
            level,
          )
        let led =
          [
            current_store_state.left,
            current_store_state.right,
            current_store_state.up,
            current_store_state.down,
            current_store_state.middle,
          ]
          |> list.any(fn(input) {
            case input {
              High -> False
              Low -> True
            }
          })
        store.set(
          store,
          Model(..current_store_state, led: case led {
            True -> High
            False -> Low
          }),
        )
      }),
    )),
  )

  Ok(process.start(fn() { check_gpio(gpio_input) }, False))
}

fn check_gpio(input: gpio.PinActor(Model, msg)) {
  gpio.sync(input)
  process.sleep(100)
  check_gpio(input)
}

fn sync_internal_led(
  store store: store.StoreActor(Model),
  gpio_led gpio_led: gpio.PinActor(Model, msg),
) {
  use model <- result.try(store.get(store))
  gpio.write(gpio_led, model.led)

  process.sleep(100)
  sync_internal_led(store, gpio_led)
}

fn sync_display(
  store store: store.StoreActor(Model),
  display_ui display_ui: ui.UserInterfaceActor,
) {
  use model <- result.try(store.get(store))
  case model {
    Model(up: Low, down: _, left: _, right: _, middle: _, led: _) -> {
      ui.update(display_ui, ui.Up)
    }
    Model(up: _, down: Low, left: _, right: _, middle: _, led: _) -> {
      ui.update(display_ui, ui.Down)
    }
    Model(up: _, down: _, left: Low, right: _, middle: _, led: _) -> {
      ui.update(display_ui, ui.Left)
    }
    Model(up: _, down: _, left: _, right: Low, middle: _, led: _) -> {
      ui.update(display_ui, ui.Right)
    }
    Model(up: _, down: _, left: _, right: _, middle: Low, led: _) -> {
      ui.update(display_ui, ui.Middle)
    }
    _ -> {
      ui.update(display_ui, ui.Blank)
    }
  }

  process.sleep(500)
  sync_display(store, display_ui)
}

fn internal_blink_pin() {
  case get_system_platform() {
    eensy.Esp32 | eensy.Pico -> 2
    _ -> 0
  }
}
