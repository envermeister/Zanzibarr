//! HDR10+ tespit durumu (flutter_rust_bridge) — roadmap #13.
//!
//! Bayrak motor tarafından, sunucudan player'a akan baytlar arasında
//! HEVC ST 2094-40 SEI'si bulununca atanır (`engine/hdr10plus.rs`); akış
//! oturumu başlarken sıfırlanır. Dart oyuncusu oynatma sırasında bu değer
//! ile bilgi satırında "HDR10+" rozeti gösterir.

/// Şu an izlenen akışta şimdiye dek HDR10+ dinamik meta verisi
/// (ST 2094-40 SEI) bulundu mu?
pub fn hdr10plus_detected() -> bool {
    crate::engine::hdr10plus::detected()
}
