///|
/// Entry URL derivation: the SDK Web Host page is configured through generic
/// URL parameters, and the contract's PCM asset declaration is what produces
/// them. No application names ever appear here.

///|
fn hex_digit(value : Int) -> Char {
  "0123456789ABCDEF".get_char(value).unwrap()
}

///|
/// Percent-encodes one query-parameter value. Unreserved characters and `/`
/// pass through; everything else becomes %XX.
pub fn percent_encode(value : String) -> String {
  let unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/"
  let out = StringBuilder()
  for ch in value {
    let text = ch.to_string()
    if unreserved.find(text) is Some(_) {
      out.write_string(text)
    } else {
      let bytes = @utf8.encode(text)
      for i in 0..<bytes.length() {
        let b = bytes[i]
        out.write_string(
          "%\{hex_digit((b >> 4).to_int())}\{hex_digit((b & 0xF).to_int())}",
        )
      }
    }
  }
  out.to_string()
}

///|
/// The `pcm=` query value for a PCM asset's bundle path (always relative,
/// always forward-slash).
fn pcm_query_value(bundle_path : String) -> String {
  let relative = if bundle_path.has_prefix("./") {
    bundle_path
  } else {
    "./\{bundle_path}"
  }
  percent_encode(relative)
}

///|
/// The bundle-relative URL path of the application entry page, including the
/// generic host configuration parameters derived from the contract.
pub fn entry_url_path(contract : ProjectContract) -> String {
  let mut pcm : AssetEntry? = None
  for asset in contract.assets {
    if asset.pcm_loop {
      pcm = Some(asset)
    }
  }
  match pcm {
    Some(asset) =>
      "index.html?pcm=\{pcm_query_value(asset.bundle_path)}&pcmLoop=1"
    None => "index.html"
  }
}
