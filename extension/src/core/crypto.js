/**
 * MD5 与签名（WBI / APP）
 *
 * MD5 不能用 crypto.subtle（WebCrypto 规范不含 MD5），所以这里是手写实现。
 */

/**
 * 将字符串按 UTF-8 转成「二进制字符串」（每个字符是一个字节）
 */
function utf8Encode(string) {
  const utftext = []
  for (let n = 0; n < string.length; n++) {
    let c = string.charCodeAt(n)
    if (c < 128) {
      utftext.push(String.fromCharCode(c))
    } else if (c < 2048) {
      utftext.push(String.fromCharCode((c >> 6) | 192))
      utftext.push(String.fromCharCode((c & 63) | 128))
    } else {
      if (c >= 55296 && c <= 56319) {
        // surrogate pair
        if (n + 1 >= string.length) {
          throw new Error('UTF-16 surrogate pair incomplete')
        }
        const c2 = string.charCodeAt(n + 1)
        c = 65536 + ((c & 1023) << 10) + (c2 & 1023)
        n++
      }
      utftext.push(String.fromCharCode((c >> 12) | 224))
      utftext.push(String.fromCharCode(((c >> 6) & 63) | 128))
      utftext.push(String.fromCharCode((c & 63) | 128))
    }
  }
  return utftext.join('')
}

function str2binl(str) {
  const bin = []
  const mask = (1 << 30) * 4 - 1 // 0xffffffff
  for (let i = 0; i < str.length * 8; i += 8) {
    const idx = i >> 5
    bin[idx] = (bin[idx] || 0) | ((str.charCodeAt(i / 8) & 0xff) << (i % 32))
    bin[idx] = bin[idx] & mask
  }
  return bin
}

function binl2hex(binarray) {
  const hexTab = '0123456789abcdef'
  let str = ''
  for (let i = 0; i < binarray.length * 4; i++) {
    const word = binarray[i >> 2]
    const byte = (word >>> ((i % 4) * 8)) & 0xff
    str += hexTab.charAt((byte >> 4) & 0x0f) + hexTab.charAt(byte & 0x0f)
  }
  return str
}

function safeAdd(x, y) {
  const lsw = (x & 0xffff) + (y & 0xffff)
  const msw = (x >> 16) + (y >> 16) + (lsw >> 16)
  return (msw << 16) | (lsw & 0xffff)
}

function bitRol(num, cnt) {
  return (num << cnt) | (num >>> (32 - cnt))
}

function md5Cmn(q, a, b, x, s, t) {
  return safeAdd(bitRol(safeAdd(safeAdd(a, q), safeAdd(x, t)), s), b)
}

function md5Ff(a, b, c, d, x, s, t) {
  return md5Cmn((b & c) | (~b & d), a, b, x, s, t)
}
function md5Gg(a, b, c, d, x, s, t) {
  return md5Cmn((b & d) | (c & ~d), a, b, x, s, t)
}
function md5Hh(a, b, c, d, x, s, t) {
  return md5Cmn(b ^ c ^ d, a, b, x, s, t)
}
function md5Ii(a, b, c, d, x, s, t) {
  return md5Cmn(c ^ (b | ~d), a, b, x, s, t)
}

function coreMd5(x, len) {
  x[len >> 5] |= 0x80 << (len % 32)
  x[(((len + 64) >>> 9) << 4) + 14] = len

  let a = 1732584193
  let b = -271733879
  let c = -1732584194
  let d = 271733878

  for (let i = 0; i < x.length; i += 16) {
    const olda = a
    const oldb = b
    const oldc = c
    const oldd = d

    a = md5Ff(a, b, c, d, x[i + 0], 7, -680876936)
    d = md5Ff(d, a, b, c, x[i + 1], 12, -389564586)
    c = md5Ff(c, d, a, b, x[i + 2], 17, 606105819)
    b = md5Ff(b, c, d, a, x[i + 3], 22, -1044525330)
    a = md5Ff(a, b, c, d, x[i + 4], 7, -176418897)
    d = md5Ff(d, a, b, c, x[i + 5], 12, 1200080426)
    c = md5Ff(c, d, a, b, x[i + 6], 17, -1473231341)
    b = md5Ff(b, c, d, a, x[i + 7], 22, -45705983)
    a = md5Ff(a, b, c, d, x[i + 8], 7, 1770035416)
    d = md5Ff(d, a, b, c, x[i + 9], 12, -1958414417)
    c = md5Ff(c, d, a, b, x[i + 10], 17, -42063)
    b = md5Ff(b, c, d, a, x[i + 11], 22, -1990404162)
    a = md5Ff(a, b, c, d, x[i + 12], 7, 1804603682)
    d = md5Ff(d, a, b, c, x[i + 13], 12, -40341101)
    c = md5Ff(c, d, a, b, x[i + 14], 17, -1502002290)
    b = md5Ff(b, c, d, a, x[i + 15], 22, 1236535329)

    a = md5Gg(a, b, c, d, x[i + 1], 5, -165796510)
    d = md5Gg(d, a, b, c, x[i + 6], 9, -1069501632)
    c = md5Gg(c, d, a, b, x[i + 11], 14, 643717713)
    b = md5Gg(b, c, d, a, x[i + 0], 20, -373897302)
    a = md5Gg(a, b, c, d, x[i + 5], 5, -701558691)
    d = md5Gg(d, a, b, c, x[i + 10], 9, 38016083)
    c = md5Gg(c, d, a, b, x[i + 15], 14, -660478335)
    b = md5Gg(b, c, d, a, x[i + 4], 20, -405537848)
    a = md5Gg(a, b, c, d, x[i + 9], 5, 568446438)
    d = md5Gg(d, a, b, c, x[i + 14], 9, -1019803690)
    c = md5Gg(c, d, a, b, x[i + 3], 14, -187363961)
    b = md5Gg(b, c, d, a, x[i + 8], 20, 1163531501)
    a = md5Gg(a, b, c, d, x[i + 13], 5, -1444681467)
    d = md5Gg(d, a, b, c, x[i + 2], 9, -51403784)
    c = md5Gg(c, d, a, b, x[i + 7], 14, 1735328473)
    b = md5Gg(b, c, d, a, x[i + 12], 20, -1926607734)

    a = md5Hh(a, b, c, d, x[i + 5], 4, -378558)
    d = md5Hh(d, a, b, c, x[i + 8], 11, -2022574463)
    c = md5Hh(c, d, a, b, x[i + 11], 16, 1839030562)
    b = md5Hh(b, c, d, a, x[i + 14], 23, -35309556)
    a = md5Hh(a, b, c, d, x[i + 1], 4, -1530992060)
    d = md5Hh(d, a, b, c, x[i + 4], 11, 1272893353)
    c = md5Hh(c, d, a, b, x[i + 7], 16, -155497632)
    b = md5Hh(b, c, d, a, x[i + 10], 23, -1094730640)
    a = md5Hh(a, b, c, d, x[i + 13], 4, 681279174)
    d = md5Hh(d, a, b, c, x[i + 0], 11, -358537222)
    c = md5Hh(c, d, a, b, x[i + 3], 16, -722521979)
    b = md5Hh(b, c, d, a, x[i + 6], 23, 76029189)
    a = md5Hh(a, b, c, d, x[i + 9], 4, -640364487)
    d = md5Hh(d, a, b, c, x[i + 12], 11, -421815835)
    c = md5Hh(c, d, a, b, x[i + 15], 16, 530742520)
    b = md5Hh(b, c, d, a, x[i + 2], 23, -995338651)

    a = md5Ii(a, b, c, d, x[i + 0], 6, -198630844)
    d = md5Ii(d, a, b, c, x[i + 7], 10, 1126891415)
    c = md5Ii(c, d, a, b, x[i + 14], 15, -1416354905)
    b = md5Ii(b, c, d, a, x[i + 5], 21, -57434055)
    a = md5Ii(a, b, c, d, x[i + 12], 6, 1700485571)
    d = md5Ii(d, a, b, c, x[i + 3], 10, -1894986606)
    c = md5Ii(c, d, a, b, x[i + 10], 15, -1051523)
    b = md5Ii(b, c, d, a, x[i + 1], 21, -2054922799)
    a = md5Ii(a, b, c, d, x[i + 8], 6, 1873313359)
    d = md5Ii(d, a, b, c, x[i + 15], 10, -30611744)
    c = md5Ii(c, d, a, b, x[i + 6], 15, -1560198380)
    b = md5Ii(b, c, d, a, x[i + 13], 21, 1309151649)
    a = md5Ii(a, b, c, d, x[i + 4], 6, -145523070)
    d = md5Ii(d, a, b, c, x[i + 11], 10, -1120210379)
    c = md5Ii(c, d, a, b, x[i + 2], 15, 718787259)
    b = md5Ii(b, c, d, a, x[i + 9], 21, -343485551)

    a = safeAdd(a, olda)
    b = safeAdd(b, oldb)
    c = safeAdd(c, oldc)
    d = safeAdd(d, oldd)
  }

  return [a, b, c, d]
}

/**
 * MD5（十六进制小写）
 * @param {string} value
 * @returns {string}
 */
export function md5(value) {
  const s = utf8Encode(String(value))
  return binl2hex(coreMd5(str2binl(s), s.length * 8))
}

/**
 * WBI 签名参数 mixin key 派生表
 * 参考 bilibili-API-collect/docs/misc/sign/wbi.md
 */
const MIXIN_KEY_ENC_TAB = [
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
  33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40,
  61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11,
  36, 20, 34, 44, 52,
]

/**
 * 从 img_key + sub_key 派生 mixin key。
 *
 * 口令不足 64 位时 raw 越界会得到 undefined 拼进结果，签出一个「格式对但内容错」
 * 的 w_rid，所以这里显式校验。
 *
 * @param {string} imgKey
 * @param {string} subKey
 * @returns {string}
 */
export function deriveMixinKey(imgKey, subKey) {
  const raw = String(imgKey) + String(subKey)
  if (raw.length < 64) {
    throw new Error(`WBI 口令长度不足 64：got ${raw.length}`)
  }
  let key = ''
  for (let i = 0; i < 32; i++) {
    key += raw[MIXIN_KEY_ENC_TAB[i]]
  }
  return key
}

/**
 * 过滤 WBI 签名 value 中的非法字符 "!'()*"
 * @param {any} value
 */
export function filterWbiValue(value) {
  return String(value).replace(/[!'()*]/g, '')
}

/**
 * WBI 签名：wts 加入参数 → 按 key 升序 → 编码拼接 → 末尾拼 mixin_key 取 MD5 得 w_rid。
 * 参考 bilibili-API-collect/docs/misc/sign/wbi.md
 *
 * @param {object} params
 * @param {string} mixinKey
 * @param {number} [timestamp] 可注入的时间戳（测试用），默认当前秒
 * @returns {object} 原参数 + wts + w_rid
 */
export function signWbi(params, mixinKey, timestamp) {
  const wts = timestamp || Math.round(Date.now() / 1000)
  const withWts = { ...params, wts }
  const sortedKeys = Object.keys(withWts).sort()

  const query = sortedKeys
    .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(filterWbiValue(withWts[k]))}`)
    .join('&')

  const w_rid = md5(`${query}${mixinKey}`)

  return { ...params, wts, w_rid }
}

/**
 * APP API 签名（与 WBI 是两套东西，TV 端扫码用）。
 * 参数加入 appkey → 按 key 升序 → query 序列化 → md5(query + appsec)。
 * 参考 bilibili-API-collect/docs/misc/sign/APP.md
 *
 * @param {object} params
 * @param {string} appkey
 * @param {string} appsec
 * @returns {object} 原参数 + appkey + sign
 */
export function signApp(params, appkey, appsec) {
  const withKey = { ...params, appkey }
  const sortedKeys = Object.keys(withKey).sort()

  const query = sortedKeys
    .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(withKey[k])}`)
    .join('&')

  const sign = md5(`${query}${appsec}`)

  const result = {}
  sortedKeys.forEach((k) => {
    result[k] = withKey[k]
  })
  result.sign = sign
  return result
}

export default { md5, deriveMixinKey, filterWbiValue, signWbi, signApp }
