/** 当前 GPS 位置（WGS-84）。 */
export interface GeoPosition {
  latitude: number;
  longitude: number;
}

/**
 * 获取当前浏览器定位（Tauri WebView / 浏览器）。失败或用户拒绝时返回 null。
 * 短超时（5s）避免长时间等待。
 */
export function getCurrentPosition(): Promise<GeoPosition | null> {
  if (typeof navigator === "undefined" || !navigator.geolocation) {
    return Promise.resolve(null);
  }
  return new Promise((resolve) => {
    const timer = window.setTimeout(() => {
      resolve(null);
    }, 5000);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        window.clearTimeout(timer);
        resolve({
          latitude: pos.coords.latitude,
          longitude: pos.coords.longitude,
        });
      },
      () => {
        window.clearTimeout(timer);
        resolve(null);
      },
      { enableHighAccuracy: false, timeout: 5000, maximumAge: 60000 },
    );
  });
}
