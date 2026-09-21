///|
/// Native-target-gated display adapter for physical Hosts: implements the
/// SDK `@driver.DisplaySink` trait over the C display bridge's strip
/// protocol (one `begin`, one `row` call per logical row, one `end`). The
/// bridge consumes rows synchronously and owns the physical DMA strip;
/// this adapter holds only one reusable logical RGB565 row, so presenting
/// a frame allocates nothing in steady state.
pub struct DeviceDisplaySink {
  row : FixedArray[Int]
}

///|
pub fn DeviceDisplaySink::new() -> DeviceDisplaySink {
  { row: FixedArray::make(@core.LOGICAL_WIDTH, 0), }
}

///|
/// Presents one fully drawn logical frame to the C display bridge, one
/// `copy_rgb565_row` call per row into the reusable row buffer. The frame
/// must be exactly the logical display size — a different size aborts
/// rather than silently stretching or clipping, and a truncated row copy
/// aborts rather than presenting partial pixels.
pub impl @driver.DisplaySink for DeviceDisplaySink with fn present(
  self : DeviceDisplaySink,
  frame~ : @graphics.FrameView,
) -> Unit {
  if frame.width() != @core.LOGICAL_WIDTH ||
    frame.height() != @core.LOGICAL_HEIGHT {
    abort("DeviceDisplaySink expects a 120 x 160 logical frame")
  }
  display_begin()
  for y in 0..<@core.LOGICAL_HEIGHT {
    let count = frame.copy_rgb565_row(y~, out=self.row)
    if count != @core.LOGICAL_WIDTH {
      abort("DeviceDisplaySink received a truncated RGB565 row")
    }
    display_row(y, self.row)
  }
  display_end()
}

///|
/// Explicitly promotes the `DisplaySink` trait methods to regular methods.
pub extend DeviceDisplaySink with @colmugx/ai-passport/driver.DisplaySink::{
  present,
}
