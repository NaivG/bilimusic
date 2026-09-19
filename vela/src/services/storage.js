import storage from '@system.storage'

function promisify(api) {
  return function (options) {
    return new Promise((resolve, reject) => {
      api({
        ...options,
        success: (data) => resolve(data),
        fail: (data, code) => reject({ data, code }),
      })
    })
  }
}

const getAsync = promisify(storage.get.bind(storage))
const setAsync = promisify(storage.set.bind(storage))
const delAsync = promisify(storage.delete.bind(storage))
const clearAsync = promisify(storage.clear.bind(storage))

export const Storage = {
  async get(key, defaultValue = '') {
    try {
      const value = await getAsync({ key, default: defaultValue })
      return value || defaultValue
    } catch (e) {
      console.error(`[Storage] get ${key} fail:`, e)
      return defaultValue
    }
  },

  async set(key, value) {
    try {
      await setAsync({ key, value: String(value) })
      return true
    } catch (e) {
      console.error(`[Storage] set ${key} fail:`, e)
      return false
    }
  },

  async remove(key) {
    try {
      await delAsync({ key })
      return true
    } catch (e) {
      console.error(`[Storage] remove ${key} fail:`, e)
      return false
    }
  },

  async clear() {
    try {
      await clearAsync({})
      return true
    } catch (e) {
      console.error('[Storage] clear fail:', e)
      return false
    }
  },

  async getJson(key, defaultValue = null) {
    const raw = await this.get(key)
    if (!raw) return defaultValue
    try {
      return JSON.parse(raw)
    } catch (e) {
      console.error(`[Storage] getJson ${key} parse fail:`, e)
      return defaultValue
    }
  },

  async setJson(key, value) {
    return this.set(key, JSON.stringify(value))
  },
}
