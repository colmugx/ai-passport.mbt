///|
/// The bundle-relative application entry page. Sound resources always come
/// from the sibling APSB bank and never configure the Host through the URL.
pub fn entry_url_path(_contract : ProjectContract) -> String {
  "index.html"
}
