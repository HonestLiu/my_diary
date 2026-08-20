#!/usr/bin/env node
/**
 * 一键发版（跨平台，Windows / macOS / Linux 均可直接运行）：
 * bump 版本 → commit → tag → push。
 * GitHub Actions 监听到 v* tag 后会自动构建 Tauri 桌面端（3 端）与 Flutter
 * 移动端（Android）并发布到 GitHub Releases。
 *
 * 用法（在仓库根目录执行）：
 *   node scripts/release.mjs               # patch：0.1.0 -> 0.1.1
 *   node scripts/release.mjs minor         # 0.1.1 -> 0.2.0
 *   node scripts/release.mjs major
 *   node scripts/release.mjs 0.3.0         # 显式指定
 *   node scripts/release.mjs --dry-run     # 只 bump 版本，不 commit / tag / push
 *
 * 环境变量：
 *   REMOTE   推送的 git remote，默认 github（本仓库的 GitHub 远端名）
 *   DRY_RUN=1  等价于 --dry-run
 */
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { bumpVersion } from './bump-version.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const bump = args.find((a) => !a.startsWith('-')) ?? 'patch';
const dryRun = args.includes('--dry-run') || process.env.DRY_RUN === '1';
const remote = process.env.REMOTE ?? 'github';

const { next } = bumpVersion(bump);

if (dryRun) {
  console.log(`（DRY_RUN）v${next}：跳过 commit / tag / push`);
  process.exit(0);
}

const files = [
  'Desktop/package.json',
  'Desktop/src-tauri/tauri.conf.json',
  'Desktop/src-tauri/Cargo.toml',
  'Mobile2/my_diary/pubspec.yaml',
];

// 用 spawnSync 逐参数调用 git，不经过 shell，避免 Windows cmd 的引号/路径问题。
const git = (args) => {
  const r = spawnSync('git', args, { cwd: root, stdio: 'inherit' });
  if (r.status !== 0) process.exit(r.status ?? 1);
};

// 只提交本次版本号改动，不夹带工作区里其它未提交变更。
git(['commit', '-m', `chore: release v${next}`, '--', ...files]);
git(['tag', `v${next}`]);
git(['push', remote, 'HEAD', '--tags']);

console.log(`✔ 已推送 v${next} 至 ${remote}，GitHub Actions 将自动构建并发布`);
