fn main() {
    cc::Build::new()
        .file("src/log_shim.c")
        .warnings(true)
        .compile("retrolife-log-shim");
    println!("cargo:rerun-if-changed=src/log_shim.c");
}
