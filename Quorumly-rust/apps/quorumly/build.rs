fn main() {
    println!("cargo:rerun-if-changed=../../dist/windows/quorumly.rc");
    println!("cargo:rerun-if-changed=../../dist/windows/quorumly.ico");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        embed_resource::compile_for(
            "../../dist/windows/quorumly.rc",
            &["quorumly"],
            embed_resource::NONE,
        )
        .manifest_required()
        .expect("Windows app icon resource compilation failed");
    }
}
