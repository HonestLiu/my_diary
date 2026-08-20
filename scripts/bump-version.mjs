#!/usr/bin/env node
/**
 * 发版版本号提升脚本 —— MyDiary 各端版本号的单一来源是 `Desktop/package.json`。
 *
 * 同步更新四处版本号：
 *   - Desktop/package.json            （npm / 前端）
 *   - Desktop/src-tauri/tauri.conf.json
 *   - Desktop/src-tauri/Cargo.toml    （Rust 包）
 *   - Mobile2/my_diary/pubspec.yaml   （Flutter，格式为 X.Y.Z+N，N 为安卓 build 号，自增）
 *
 * 用法（在仓库根目录执行）：
 *   node scripts/bump-version.mjs            # 默认 patch：0.1.0 -> 0.1.1
 *   node scripts/bump-version.mjs patch      # 同上
 *   node scripts/bump-version.mjs minor      # 0.1.1 -> 0.2.0
 *   node scripts/bump-version.mjs major      # 0.2.0 -> 1.0.0
 *   node scripts/bump-version.mjs 0.3.0      # 显式指定下一版本
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

const read = (rel) => readFileSync(join(root, rel), 'utf8');
const write = (rel, content) => writeFileSync(join(root, rel), content);

/**
 * 计算下一版本并同步写入各端版本文件。
 * @param {string} [bumpArg] patch | minor | major | 显式 x.y.z
 * @returns {{current: string, next: string, buildNo: number}}
 * @throws {Error} 参数非法或无需更新时抛错
 */
export function bumpVersion(bumpArg = 'patch') {
  // ---- 读取当前版本（唯一来源） ----
  const pkgPath = 'Desktop/package.json';
  const pkg = JSON.parse(read(pkgPath));
  const current = pkg.version;

  // ---- 计算下一版本 ----
  const arg = String(bumpArg).trim();
  let next;
  if (/^\d+\.\d+\.\d+$/.test(arg)) {
    next = arg;
  } else {
    const [major, minor, patch] = current.split('.').map(Number);
    switch (arg) {
      case 'major':
        next = `${major + 1}.0.0`;
        break;
      case 'minor':
        next = `${major}.${minor + 1}.0`;
        break;
      case 'patch':
        next = `${major}.${minor}.${patch + 1}`;
        break;
      default:
        throw new Error(`未知参数: "${arg}"（应为 patch | minor | major 或 x.y.z）`);
    }
  }

  if (next === current) {
    throw new Error(`版本未变化（${current}），无需更新`);
  }

  // ---- 1) Desktop/package.json ----
  pkg.version = next;
  write(pkgPath, JSON.stringify(pkg, null, 2) + '\n');

  // ---- 2) Desktop/src-tauri/tauri.conf.json ----
  const tauriPath = 'Desktop/src-tauri/tauri.conf.json';
  const tauri = JSON.parse(read(tauriPath));
  tauri.version = next;
  write(tauriPath, JSON.stringify(tauri, null, 2) + '\n');

  // ---- 3) Desktop/src-tauri/Cargo.toml：仅替换 [package] 下的 version ----
  // 依赖项（如 tauri = { version = "2" }）格式不同，不会被误伤。
  const cargoPath = 'Desktop/src-tauri/Cargo.toml';
  const cargo = read(cargoPath);
  const cargoUpdated = cargo.replace(
    /(\[package\][\s\S]*?^version = ")[\d.]+(")/m,
    `$1${next}$2`,
  );
  if (cargoUpdated === cargo) {
    throw new Error('Cargo.toml 中未找到 [package] 的 version，未更新');
  }
  write(cargoPath, cargoUpdated);

  // ---- 4) Mobile2/my_diary/pubspec.yaml：X.Y.Z+N，build 号自增 ----
  const pubspecPath = 'Mobile2/my_diary/pubspec.yaml';
  const pubspec = read(pubspecPath);
  const m = pubspec.match(/^version:\s*\d+\.\d+\.\d+\+(\d+)\s*$/m);
  const buildNo = m ? Number(m[1]) + 1 : 1;
  const pubspecUpdated = pubspec.replace(
    /^version:\s*[\d.]+\+\d+\s*$/m,
    `version: ${next}+${buildNo}\n`,
  );
  if (pubspecUpdated === pubspec) {
    throw new Error('pubspec.yaml 中未找到 version 行，未更新');
  }
  write(pubspecPath, pubspecUpdated);

  console.log(`✔ 版本已更新：${current} -> ${next}（Flutter build ${buildNo}）`);
  for (const p of [pkgPath, tauriPath, cargoPath, pubspecPath]) {
    console.log(`   · ${p}`);
  }
  return { current, next, buildNo };
}

// 直接执行时（node scripts/bump-version.mjs）才跑 CLI；被 release.mjs import 时不重复执行。
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    bumpVersion(process.argv[2]);
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}
