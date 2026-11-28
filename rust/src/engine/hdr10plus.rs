//! HDR10+ (SMPTE ST 2094-40) çalışma zamanı tespiti (roadmap #13).
//!
//! mpv/FFmpeg ST 2094-40 sinyalini çalışma zamanında bir property olarak
//! vermez; tespit bu yüzden doğrudan servis EDİLEN akış baytlarında yapılır:
//! HEVC önek-SEI NAL'lerinde `payload_type = 2094` kodlaması (255 yalımı
//! 8 kez + 54) aranır. Baytlar zaten range sunucusundan player'a giderken
//! geçer — ek istik istenmez, tembel akış kuralı (§AGENTS 4.3) bozulmaz;
//! kullanıcı izlemedikçe hiçbir tarama olmaz.
//!
//! Tarama penceresi akışın ilk 32 MB'ıdır: dinamik meta veriler ilk
//! GOP'larda başlar (her sahne başında SEI tekrarlanır); pencere aşılınca
//! tarama durur. Matroska içi HEVC'de start kodları ham biçimde bulunur;
//! MP4'in uzunluk-önekli paketlerinde start kod yoktur — bu kapsayıcılar
//! için tespit yapılamaz (bilinçli sınır; arama sonuçlarındaki release-adı
//! rozeti o yaygınlığı zaten taşır).

use std::collections::HashSet;
use std::sync::Mutex;

/// Aranan tam işaret: start kodunun son baytı (`01`) + HEVC önek-SEI
/// başlığı (`0x4E 0x01`) + payload türü 2094 kodlaması (`0xFF`×8 + `0x36`).
const ANCHOR: [u8; 12] = [
    0x01, 0x4E, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x36,
];

/// Hash-mark olasılığı dışlanan start kodu doğrulaması: işaretten hemen
/// önceki iki bayt `00 00` olmalı (3 ve 4 baytlı start kodları birlikte
/// karşılanır: `00 00 01 …` / `00 00 00 01 …`).
const START_CODE_ZEROES: [u8; 2] = [0x00, 0x00];

/// Akışın taranan ilk penceresi.
pub const SCAN_WINDOW_BYTES: u64 = 32 * 1024 * 1024;

static DETECTED: Mutex<Option<HashSet<u64>>> = Mutex::new(None);

/// Global bayrak, paralel koşan birim testlerde paylaşımlıdır; bayrağı
/// sıfırlayan/atan tüm testler bu kitle alınır (server.rs e2e testi dahil).
#[cfg(test)]
pub static TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// Tek akışlı/test oturumu (0) için geriye uyumlu sıfırlama.
pub fn reset() {
    reset_for_session(0);
}

/// Yeni bir akış oturumu başlarken yalnız onun bayrağını sıfırla.
pub fn reset_for_session(session_id: u64) {
    if let Some(detected) = DETECTED.lock().expect("hdr10+ durumu").as_mut() {
        detected.remove(&session_id);
    }
}

/// Tek akışlı/test oturumu için geriye uyumlu sorgu.
pub fn detected() -> bool {
    detected_for_session(0)
}

/// İzlenen akışta şimdiye dek HDR10+ SEI'si görüldü mü?
pub fn detected_for_session(session_id: u64) -> bool {
    DETECTED
        .lock()
        .expect("hdr10+ durumu")
        .as_ref()
        .is_some_and(|detected| detected.contains(&session_id))
}

fn mark_detected(session_id: u64) {
    DETECTED
        .lock()
        .expect("hdr10+ durumu")
        .get_or_insert_with(HashSet::new)
        .insert(session_id);
}

/// Saf tarama: `tail` mutlak `chunk_absolute_offset`'ten önceki son
/// baytlardır (parça sınırlarında bölünen işaretler için); `chunk` o
/// ofsetten başlar. İşaret bulunursa bayrak atanır ve işaretin mutlak
/// dosya ofseti döner.
pub fn scan_chunk(chunk_absolute_offset: u64, tail: &[u8], chunk: &[u8]) -> Option<u64> {
    scan_chunk_for_session(0, chunk_absolute_offset, tail, chunk)
}

fn scan_chunk_for_session(
    session_id: u64,
    chunk_absolute_offset: u64,
    tail: &[u8],
    chunk: &[u8],
) -> Option<u64> {
    let mut haystack = Vec::with_capacity(tail.len() + chunk.len());
    haystack.extend_from_slice(tail);
    haystack.extend_from_slice(chunk);

    let mut from = 0;
    while from + ANCHOR.len() <= haystack.len() {
        let Some(relative) = find_anchor(&haystack[from..]) else {
            break;
        };
        let position = from + relative;
        // Start kodu doğrulaması: işaretten önceki iki bayt 00 00.
        if position >= 2 && haystack[position - 2..position] == START_CODE_ZEROES {
            let absolute = chunk_absolute_offset as i64 + position as i64 - tail.len() as i64;
            if absolute >= 0 {
                mark_detected(session_id);
                return Some(absolute as u64);
            }
        }
        from = position + 1;
    }
    None
}

/// Basit bayt alt-dizisi araması (`ANCHOR` 12 bayt olduğundan memchr-kural
/// yerine doğrudan pencereli karşılaştırma yeter de artar).
fn find_anchor(haystack: &[u8]) -> Option<usize> {
    if haystack.len() < ANCHOR.len() {
        return None;
    }
    haystack
        .windows(ANCHOR.len())
        .position(|window| window == ANCHOR)
}

/// Sunucunun yazma ucu: player'a giden her bayt taramadan geçer
/// ([`super::server`] bunu `AsyncWrite` sarmalayıcısı olarak kullanır).
///
/// `offset` yazılan baytın mutlak dosya ofsetidir; pencere dışına çıkınca
/// tarama kendini kapatır.
pub struct ScanSink<W> {
    inner: W,
    offset: u64,
    window: u64,
    tail: Vec<u8>,
    active: bool,
    session_id: u64,
}

impl<W> ScanSink<W> {
    pub fn new(inner: W, start_offset: u64) -> Self {
        Self::new_with_window(inner, start_offset, SCAN_WINDOW_BYTES)
    }

    pub fn new_for_session(inner: W, start_offset: u64, session_id: u64) -> Self {
        let active = start_offset < SCAN_WINDOW_BYTES;
        Self {
            inner,
            offset: start_offset,
            window: SCAN_WINDOW_BYTES,
            tail: Vec::new(),
            active,
            session_id,
        }
    }

    pub(crate) fn new_with_window(inner: W, start_offset: u64, window: u64) -> Self {
        let active = start_offset < window;
        Self {
            inner,
            offset: start_offset,
            window,
            tail: Vec::new(),
            active,
            session_id: 0,
        }
    }

    /// Yazılan (başarılı `write` erimleri) baytları tarar. Sarmalayıcı yalnız
    /// yazılan miktarla çağırdığından kısmi-yazma yeniden denemelerinde çift
    /// sayım olmaz.
    pub fn feed(&mut self, written: &[u8]) {
        if !self.active {
            return;
        }
        // Pencere kesin taranan üst sınırdır: onun ötesindeki baytlar hiç
        // aranmaz (ofset gerçek yazma konumu olarak akar).
        let scan_len = (self.window - self.offset).min(written.len() as u64) as usize;
        let scan = &written[..scan_len];
        if scan_chunk_for_session(self.session_id, self.offset, &self.tail, scan).is_some() {
            self.active = false;
            return;
        }
        // Kuyruk: parça sınırında bölünen işaret için son baytlar.
        let keep = ANCHOR.len() - 1 + START_CODE_ZEROES.len();
        let mut combined = Vec::with_capacity(self.tail.len() + scan.len());
        combined.extend_from_slice(&self.tail);
        combined.extend_from_slice(scan);
        let start = combined.len().saturating_sub(keep);
        self.tail = combined[start..].to_vec();
        self.offset += written.len() as u64;
        if self.offset >= self.window {
            self.active = false;
        }
    }
}

impl<W: tokio::io::AsyncWrite + Unpin> tokio::io::AsyncWrite for ScanSink<W> {
    fn poll_write(
        self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &[u8],
    ) -> std::task::Poll<std::io::Result<usize>> {
        let this = self.get_mut();
        let result = std::pin::Pin::new(&mut this.inner).poll_write(cx, buf);
        if let std::task::Poll::Ready(Ok(count)) = &result {
            this.feed(&buf[..*count]);
        }
        result
    }

    fn poll_flush(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SEI_HEADER: [u8; 2] = [0x4E, 0x01];
    const PAYLOAD_TYPE_2094: [u8; 9] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x36];

    /// Sentetik HDR10+ SEI NAL'i: start kodu + baslik + tur kodlamasi +
    /// kisa bir govde.
    fn sei_nal() -> Vec<u8> {
        let mut bytes = vec![0x00, 0x00, 0x00, 0x01, 0x4E, 0x01];
        bytes.extend_from_slice(&PAYLOAD_TYPE_2094);
        bytes.extend_from_slice(&[0x03, 0x00, 0x01, 0x02, 0x80]);
        bytes
    }

    #[test]
    fn sabit_isaret_butunlugu() {
        let _guard = super::TEST_LOCK.lock().unwrap();
        let mut composed = vec![0x01];
        composed.extend_from_slice(&SEI_HEADER);
        composed.extend_from_slice(&PAYLOAD_TYPE_2094);
        assert_eq!(composed.as_slice(), ANCHOR);
    }

    #[test]
    fn isaret_tek_parca_icinde_bulunur() {
        let _guard = super::TEST_LOCK.lock().unwrap();
        reset();
        let mut data = vec![0u8; 512];
        let nal = sei_nal();
        data[100..100 + nal.len()].copy_from_slice(&nal);
        let offset = scan_chunk(0, &[], &data);
        assert_eq!(offset, Some(103)); // start kodunun 01 bayti
        assert!(detected());
        reset();
    }

    #[test]
    fn session_bayraklari_birbirini_etkilemez() {
        let _guard = super::TEST_LOCK.lock().unwrap();
        reset_for_session(7);
        reset_for_session(8);
        let mut data = vec![0u8; 512];
        let nal = sei_nal();
        data[100..100 + nal.len()].copy_from_slice(&nal);
        assert_eq!(scan_chunk_for_session(7, 0, &[], &data), Some(103));
        assert!(detected_for_session(7));
        assert!(!detected_for_session(8));
        reset_for_session(7);
        assert!(!detected_for_session(7));
        assert!(!detected_for_session(8));
    }

    #[test]
    fn isaret_parca_sinirinda_kuyruk_ile_bulunur() {
        let _guard = super::TEST_LOCK.lock().unwrap();
        reset();
        let data = sei_nal();
        let (head, rest) = data.split_at(7);
        let mut sink = ScanSink::new_with_window(1u8, 0, 4096);
        sink.feed(head);
        assert!(!detected());
        sink.feed(rest);
        assert!(detected());
        reset();
    }

    #[test]
    fn acik_uclu_ofset_fazladan_kuyraktan_tarar() {
        let _guard = super::TEST_LOCK.lock().unwrap();
        reset();
        // Sunucu sirali yazarken kuyruk parcalar arasi tasinir; range
        // baslangici sifirdan farkliyken mutlak ofset dogru hesaplanir.
        let data = sei_nal();
        let mut sink = ScanSink::new_with_window(1u8, 1000, 2048);
        let (head, rest) = data.split_at(4);
        sink.feed(head);
        sink.feed(rest);
        assert!(detected());
        reset();
    }

    #[test]
    fn start_kodu_dogrulamasi_haydeleri_elar() {
        let _guard = super::TEST_LOCK.lock().unwrap();
        reset();
        let mut data = vec![0x11u8; 256];
        let mut anchor = vec![0x01, 0x4E, 0x01];
        anchor.extend_from_slice(&PAYLOAD_TYPE_2094);
        data[40..40 + anchor.len()].copy_from_slice(&anchor);
        assert_eq!(scan_chunk(0, &[], &data), None);
        assert!(!detected());
    }

    #[test]
    fn yanlis_pozitifler_elar() {
        let _guard = super::TEST_LOCK.lock().unwrap();
        reset();
        assert_eq!(scan_chunk(0, &[], &vec![0xFF; 1024]), None);
        let mut wrong = vec![0x00, 0x00, 0x00, 0x01, 0x4E, 0x01, 0x01, 0x18];
        wrong.extend_from_slice(&[0u8; 64]);
        assert_eq!(scan_chunk(0, &[], &wrong), None);
        assert!(!detected());
    }

    #[test]
    fn pencere_disi_hic_taranmaz() {
        let _guard = super::TEST_LOCK.lock().unwrap();
        reset();
        let mut data = vec![0u8; 128];
        let nal = sei_nal();
        data[70..70 + nal.len()].copy_from_slice(&nal);
        let mut sink = ScanSink::new_with_window(1u8, 0, 64);
        sink.feed(&data);
        assert!(!detected());
        reset();
        let mut small = vec![0u8; 128];
        small[60..60 + nal.len()].copy_from_slice(&nal);
        let mut sink = ScanSink::new_with_window(1u8, 0, 128);
        sink.feed(&small);
        assert!(detected());
        reset();
    }

    #[test]
    fn bayrak_sifirlanabilir() {
        let _guard = super::TEST_LOCK.lock().unwrap();
        reset();
        let data = sei_nal();
        let mut sink = ScanSink::new_with_window(1u8, 0, 128);
        sink.feed(&data);
        assert!(detected());
        reset();
        assert!(!detected());
    }
}
