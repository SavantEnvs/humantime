#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &str| {
    let _ = humantime::parse_duration(data);
    let _ = humantime::parse_rfc3339(data);
    let _ = humantime::parse_rfc3339_weak(data);
});
