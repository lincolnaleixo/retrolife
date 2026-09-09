use std::collections::VecDeque;
use std::sync::atomic::{AtomicU16, Ordering};

pub(crate) const INPUT_PORTS: usize = 4;
pub(crate) const MAX_VIDEO_WIDTH: u32 = 4096;
pub(crate) const MAX_VIDEO_HEIGHT: u32 = 4096;
pub(crate) const MAX_VIDEO_BYTES: usize = 64 * 1024 * 1024;
pub(crate) const MAX_AUDIO_BUFFER_FRAMES: usize = 8192;

/// Libretro joypad button identifiers represented as bits in an input mask.
///
/// The values follow the `RETRO_DEVICE_ID_JOYPAD_*` identifiers from the
/// libretro API. Keeping the mask in the emulation crate lets a frontend map
/// its own actions without making the core depend on Godot input types.
pub const JOYPAD_B: u16 = 1 << 0;
pub const JOYPAD_Y: u16 = 1 << 1;
pub const JOYPAD_SELECT: u16 = 1 << 2;
pub const JOYPAD_START: u16 = 1 << 3;
pub const JOYPAD_UP: u16 = 1 << 4;
pub const JOYPAD_DOWN: u16 = 1 << 5;
pub const JOYPAD_LEFT: u16 = 1 << 6;
pub const JOYPAD_RIGHT: u16 = 1 << 7;
pub const JOYPAD_A: u16 = 1 << 8;
pub const JOYPAD_X: u16 = 1 << 9;
pub const JOYPAD_L: u16 = 1 << 10;
pub const JOYPAD_R: u16 = 1 << 11;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum PixelFormat {
    ZeroRgb1555,
    Xrgb8888,
    Rgb565,
}

impl PixelFormat {
    pub(crate) fn name(self) -> &'static str {
        match self {
            Self::ZeroRgb1555 => "0rgb1555",
            Self::Xrgb8888 => "xrgb8888",
            Self::Rgb565 => "rgb565",
        }
    }

    pub(crate) fn bytes_per_pixel(self) -> usize {
        match self {
            Self::ZeroRgb1555 | Self::Rgb565 => 2,
            Self::Xrgb8888 => 4,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VideoFrameInfo {
    pub sequence: u64,
    pub width: u32,
    pub height: u32,
    pub row_bytes: usize,
    pub byte_size: usize,
    pub pixel_format: &'static str,
    pub generated_at_ns: u64,
    pub duplicate: bool,
    pub overwritten_frames: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VideoFrame {
    pub info: VideoFrameInfo,
    /// A tightly packed RGBA8888 frame in row-major order.
    pub rgba: Vec<u8>,
}

pub(crate) struct VideoSlot {
    current: Option<VideoFrame>,
    last_consumed_sequence: u64,
    overwritten_frames: u64,
    next_sequence: u64,
}

impl VideoSlot {
    pub(crate) fn new() -> Self {
        Self {
            current: None,
            last_consumed_sequence: 0,
            overwritten_frames: 0,
            next_sequence: 1,
        }
    }

    pub(crate) fn publish(
        &mut self,
        rgba: Vec<u8>,
        width: u32,
        height: u32,
        pixel_format: &'static str,
        generated_at_ns: u64,
        duplicate: bool,
    ) {
        if let Some(current) = &self.current
            && current.info.sequence > self.last_consumed_sequence
        {
            self.overwritten_frames = self.overwritten_frames.saturating_add(1);
        }

        let sequence = self.next_sequence;
        self.next_sequence = self.next_sequence.saturating_add(1);
        self.current = Some(VideoFrame {
            info: VideoFrameInfo {
                sequence,
                width,
                height,
                row_bytes: width as usize * 4,
                byte_size: rgba.len(),
                pixel_format,
                generated_at_ns,
                duplicate,
                overwritten_frames: self.overwritten_frames,
            },
            rgba,
        });
    }

    pub(crate) fn publish_duplicate(&mut self, generated_at_ns: u64) {
        let Some(current) = self.current.as_ref().cloned() else {
            return;
        };
        let sequence = self.next_sequence;
        self.next_sequence = self.next_sequence.saturating_add(1);
        self.current = Some(VideoFrame {
            info: VideoFrameInfo {
                sequence,
                width: current.info.width,
                height: current.info.height,
                row_bytes: current.info.row_bytes,
                byte_size: current.info.byte_size,
                pixel_format: current.info.pixel_format,
                generated_at_ns,
                duplicate: true,
                overwritten_frames: self.overwritten_frames,
            },
            rgba: current.rgba,
        });
    }

    pub(crate) fn clear(&mut self) {
        self.current = None;
        self.last_consumed_sequence = 0;
        self.overwritten_frames = 0;
        self.next_sequence = 1;
    }

    pub(crate) fn latest(&self) -> Option<VideoFrame> {
        self.current.clone()
    }

    pub(crate) fn after(&mut self, after_sequence: u64) -> Option<VideoFrame> {
        let frame = self.current.as_ref()?;
        if frame.info.sequence <= after_sequence {
            return None;
        }
        self.last_consumed_sequence = frame.info.sequence;
        Some(frame.clone())
    }

    pub(crate) fn sequence(&self) -> u64 {
        self.current
            .as_ref()
            .map(|frame| frame.info.sequence)
            .unwrap_or(0)
    }

    pub(crate) fn overwritten_frames(&self) -> u64 {
        self.overwritten_frames
    }
}

#[derive(Debug)]
pub(crate) struct AudioRing {
    samples: VecDeque<i16>,
    dropped_frames: u64,
    max_frames: usize,
}

impl AudioRing {
    pub(crate) fn new() -> Self {
        Self {
            samples: VecDeque::with_capacity(MAX_AUDIO_BUFFER_FRAMES * 2),
            dropped_frames: 0,
            max_frames: MAX_AUDIO_BUFFER_FRAMES,
        }
    }

    pub(crate) fn push_interleaved_stereo(&mut self, samples: &[i16]) {
        let sample_count = samples.len() - (samples.len() % 2);
        let max_samples = self.max_frames * 2;
        let mut first = sample_count.saturating_sub(max_samples);
        if !first.is_multiple_of(2) {
            first += 1;
        }
        if first > 0 {
            self.dropped_frames = self.dropped_frames.saturating_add((first / 2) as u64);
        }

        for sample in &samples[first.min(sample_count)..sample_count] {
            self.samples.push_back(*sample);
        }

        while self.samples.len() > max_samples {
            self.samples.pop_front();
            self.samples.pop_front();
            self.dropped_frames = self.dropped_frames.saturating_add(1);
        }
    }

    pub(crate) fn drain_frames(&mut self, frames: usize) -> Vec<i16> {
        let count = frames.min(self.samples.len() / 2) * 2;
        (0..count)
            .filter_map(|_| self.samples.pop_front())
            .collect()
    }

    pub(crate) fn buffered_frames(&self) -> usize {
        self.samples.len() / 2
    }

    pub(crate) fn dropped_frames(&self) -> u64 {
        self.dropped_frames
    }

    pub(crate) fn clear(&mut self) {
        self.samples.clear();
        self.dropped_frames = 0;
    }
}

#[derive(Debug)]
pub(crate) struct AtomicInputs {
    masks: [AtomicU16; INPUT_PORTS],
}

impl AtomicInputs {
    pub(crate) fn new() -> Self {
        Self {
            masks: std::array::from_fn(|_| AtomicU16::new(0)),
        }
    }

    pub(crate) fn set(&self, player: usize, mask: u16) -> bool {
        let Some(input) = self.masks.get(player) else {
            return false;
        };
        input.store(mask, Ordering::Release);
        true
    }

    pub(crate) fn get(&self, player: usize) -> u16 {
        self.masks
            .get(player)
            .map(|input| input.load(Ordering::Acquire))
            .unwrap_or(0)
    }

    pub(crate) fn clear(&self) {
        for input in &self.masks {
            input.store(0, Ordering::Release);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn video_slot_tracks_latest_frame_and_overwrites() {
        let mut slot = VideoSlot::new();
        slot.publish(vec![255; 4], 1, 1, "rgba8888", 10, false);
        slot.publish(vec![0; 4], 1, 1, "rgba8888", 20, false);

        assert_eq!(slot.sequence(), 2);
        assert_eq!(slot.overwritten_frames(), 1);
        assert_eq!(slot.after(1).expect("new frame").rgba, vec![0; 4]);

        slot.publish_duplicate(30);
        let duplicate = slot.latest().expect("duplicate frame");
        assert!(duplicate.info.duplicate);
        assert_eq!(duplicate.info.sequence, 3);
        assert_eq!(slot.overwritten_frames(), 1);
    }

    #[test]
    fn audio_ring_is_bounded_and_drops_whole_frames() {
        let mut ring = AudioRing::new();
        let samples = vec![7_i16; (MAX_AUDIO_BUFFER_FRAMES + 3) * 2];
        ring.push_interleaved_stereo(&samples);

        assert_eq!(ring.buffered_frames(), MAX_AUDIO_BUFFER_FRAMES);
        assert_eq!(ring.dropped_frames(), 3);
        assert_eq!(ring.drain_frames(2).len(), 4);
        assert_eq!(ring.buffered_frames(), MAX_AUDIO_BUFFER_FRAMES - 2);
    }

    #[test]
    fn atomic_inputs_keep_the_latest_mask_per_player() {
        let inputs = AtomicInputs::new();
        assert!(inputs.set(0, JOYPAD_A | JOYPAD_START));
        assert!(inputs.set(3, JOYPAD_LEFT));
        assert_eq!(inputs.get(0), JOYPAD_A | JOYPAD_START);
        assert_eq!(inputs.get(3), JOYPAD_LEFT);
        assert!(!inputs.set(INPUT_PORTS, JOYPAD_B));
        inputs.clear();
        assert_eq!(inputs.get(0), 0);
        assert_eq!(inputs.get(3), 0);
    }
}
