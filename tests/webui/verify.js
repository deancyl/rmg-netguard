'use strict';

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const root = path.join(__dirname, '..', '..');
const htmlFile = path.join(root, 'module', 'webroot', 'index.html');
const outDir = path.join(__dirname, 'shots');
fs.mkdirSync(outDir, { recursive: true });

const STATUS = [
  '{"ts":"__TS__","state":"RISK_COEXIST","vpn":1,"vpn_if":"tun0","hijack":1,"agh_pid":8594,"agh_port":1,"mihomo_port":0,"dns_ms":"22","client":"meta","mode":"observe","track":"A"}',
  '---',
  'track A: hijack ATTACHED',
  'vpn=1 if=tun0',
  'client=meta mode=observe integration=on profile=patched',
  'filter_probe=BLOCKED',
  'filter_probe_wedge=UNKNOWN',
  'querylog_age=401',
  'profile: f27ccf1a-6eb6-48f1-8962-d90e8c88be6d',
  'patched: patched backup: yes drifted: no'
].join('\n');

let pass = 0;
let fail = 0;

function check(name, cond, detail) {
  if (cond) {
    pass++;
    console.log('  PASS  ' + name);
  } else {
    fail++;
    console.log('  FAIL  ' + name + (detail ? '  -> ' + detail : ''));
  }
}

async function main() {
  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: { width: 384, height: 823 },
    deviceScaleFactor: 2.75,
    isMobile: true,
    hasTouch: true
  });
  const page = await context.newPage();
  const errors = [];

  page.on('pageerror', error => errors.push('PAGEERROR: ' + error.message));
  page.on('console', message => {
    if (message.type() === 'error') { errors.push('CONSOLE: ' + message.text()); }
  });

  await page.addInitScript(({ statusTemplate }) => {
    const commands = [];
    const intervals = [];
    const nativeSetInterval = window.setInterval.bind(window);
    window.__cmds = commands;
    window.__intervals = intervals;
    window.__fail = null;
    window.setInterval = function (fn, delay) {
      intervals.push(delay);
      return nativeSetInterval(fn, delay);
    };

    function stamp() {
      const date = new Date();
      const pad = value => String(value).padStart(2, '0');
      return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' +
        pad(date.getDate()) + ' ' + pad(date.getHours()) + ':' +
        pad(date.getMinutes()) + ':' + pad(date.getSeconds());
    }

    function statusText(includeProbes) {
      let lines = statusTemplate.replace('__TS__', stamp()).split('\n');
      if (!includeProbes) {
        lines = lines.filter(line => !/filter_probe|querylog_age/.test(line));
      }
      // Deliberately leave state.json's mode stale. The controller output must
      // be the single live source for both the header and detail card.
      return lines.join('\n').replace('mode=observe', 'mode=auto');
    }

    function run(cmd) {
      if (cmd.includes('webui.sh status_fast')) {
        return { code: 0, out: statusText(false), err: '' };
      }
      if (cmd.includes('webui.sh status')) {
        return { code: 0, out: statusText(true), err: '' };
      }
      if (window.__fail && cmd.includes(window.__fail)) {
        return { code: 1, out: 'simulated failure', err: 'boom' };
      }
      if (cmd.includes('webui.sh probe')) return { code: 0, out: '== 体检 ==\n1) VPN : tun0', err: '' };
      if (cmd.includes('webui.sh audit')) return { code: 0, out: '== 审计 ==\nWARN x4', err: '' };
      if (cmd.includes('webui.sh stats')) return { code: 0, out: '== 统计 ==\ntotal 481', err: '' };
      if (cmd.includes('webui.sh log')) return { code: 0, out: '== 日志 ==\n2026-10-16 START', err: '' };
      if (cmd.includes('webui.sh mode_auto')) return { code: 0, out: 'OK: mode=auto', err: '' };
      if (cmd.includes('webui.sh mode_observe')) return { code: 0, out: 'OK: mode=observe', err: '' };
      if (cmd.includes('webui.sh integ_on')) return { code: 0, out: 'OK: patched f27ccf1a', err: '' };
      if (cmd.includes('webui.sh integ_off')) return { code: 0, out: 'OK: reverted f27ccf1a', err: '' };
      if (cmd.includes('controller.sh detach')) return { code: 0, out: 'OK: detached (track B)', err: '' };
      if (cmd.includes('controller.sh attach')) return { code: 0, out: 'OK: attached (track A)', err: '' };
      return { code: 0, out: 'RAN: ' + cmd, err: '' };
    }

    window.ksu = {
      exec(cmd, options, cb) {
        if (typeof options === 'string' && options !== '{}' && typeof cb !== 'string') {
          throw new Error('invalid callback bridge');
        }
        commands.push(cmd);
        const result = run(cmd);
        const callback = typeof cb === 'string' ? cb : null;
        const delay = cmd.includes('status_fast') ? 120 : (cmd.includes('webui.sh status') ? 900 : 300);
        setTimeout(() => {
          if (callback && typeof window[callback] === 'function') {
            window[callback](result.code, result.out, result.err);
          }
        }, delay);
        return '';
      },
      toast() {},
      moduleInfo() { return '{}'; }
    };
  }, { statusTemplate: STATUS });

  await page.goto('file:///' + htmlFile.replace(/\\/g, '/'));
  await page.waitForTimeout(450);

  console.log('\n=== A. initial paint ===');
  const initial = await page.evaluate(() => ({
    commands: window.__cmds.slice(),
    intervals: window.__intervals.slice(),
    busy: document.getElementById('busybar').className,
    probe: document.getElementById('hb_probe').textContent,
    mode: document.getElementById('hb_mode').textContent,
    modeCard: document.getElementById('st_mode2').textContent
  }));
  check('initial command uses status_fast', initial.commands.some(cmd => cmd.includes('status_fast')));
  check('initial command skips slow status', !initial.commands.some(cmd => /webui\.sh status$/.test(cmd)));
  check('panel unlocked after initial paint', initial.busy === '');
  check('probe starts as not tested', initial.probe.includes('未检测'), initial.probe);
  check('30-second auto refresh timer starts', initial.intervals.includes(30000), JSON.stringify(initial.intervals));
  check('header uses live controller mode', initial.mode === '自动切换', initial.mode);
  check('detail card uses same live mode', initial.modeCard === '自动切换', initial.modeCard);

  console.log('\n=== B. layout ===');
  const layout = await page.evaluate(() => ({
    height: document.documentElement.scrollHeight,
    detailsClosed: !document.querySelector('details').open
  }));
  check('page remains compact', layout.height < 1100, String(layout.height));
  check('detailed output collapsed by default', layout.detailsClosed);

  console.log('\n=== C. no blocking dialog ===');
  const source = fs.readFileSync(htmlFile, 'utf8');
  check('no window.confirm call', !/window\.confirm\s*\(/.test(source.replace(/\/\/.*/g, '')));

  console.log('\n=== D. feedback and actions ===');
  const button = label => page.locator('.btns button', { hasText: label }).first();
  const actions = [
    ['刷新状态', false],
    ['一键体检', false],
    ['规则审计', false],
    ['拦截统计', false],
    ['事件日志（最近 20 条）', false],
    ['摘除 AGH 劫持', true],
    ['恢复 AGH 劫持', true]
  ];

  for (const [label, needsConfirm] of actions) {
    await page.evaluate(() => { document.getElementById('result').className = ''; });
    await button(label).click();
    await page.waitForTimeout(180);
    const during = await page.evaluate(() => ({
      result: document.getElementById('result').textContent,
      confirm: document.getElementById('confbar').className
    }));
    check('[' + label + '] immediate acknowledgement', during.result.length > 0);
    if (needsConfirm) {
      check('[' + label + '] in-panel confirmation opened', during.confirm === 'on');
      await page.click('#confyes');
    }
    await page.waitForTimeout(1250);
    const after = await page.evaluate(() => ({
      className: document.getElementById('result').className,
      busy: document.getElementById('busybar').className,
      actionDisabled: Array.from(document.querySelectorAll('.btns button'))
        .filter(el => el.id !== 'btn_obs' && el.id !== 'btn_auto')
        .filter(el => el.disabled).length,
      modeDisabled: ['btn_obs', 'btn_auto']
        .filter(id => document.getElementById(id).disabled).length
    }));
    check('[' + label + '] finished with ok/err feedback', /ok|err/.test(after.className));
    check('[' + label + '] unlocked', after.busy === '' && after.actionDisabled === 0);
    check('[' + label + '] exactly one current-mode lock', after.modeDisabled === 1);
  }

  console.log('\n=== E. probe wording ===');
  const probeText = await page.textContent('#st_probe');
  check('inconsistent probes are neutral', probeText.includes('双探针结果不一致'), probeText);
  check('probe does not claim AGH is degraded', !probeText.includes('AGH 退化'), probeText);

  console.log('\n=== F. busy re-entry is acknowledged ===');
  await button('一键体检').click();
  await page.waitForTimeout(40);
  await page.evaluate(() => window.run('probe'));
  const busyNote = await page.textContent('#result');
  check('busy re-entry produces a note', /还在执行|请稍候/.test(busyNote), busyNote);
  await page.waitForTimeout(600);

  console.log('\n=== G. confirmation cancellation ===');
  await button('摘除 AGH 劫持').click();
  await page.click('#confno');
  const cancelled = await page.evaluate(() => ({
    text: document.getElementById('result').textContent,
    bar: document.getElementById('confbar').className
  }));
  check('confirm bar closes', cancelled.bar === '');
  check('cancel is acknowledged', cancelled.text.includes('取消'), cancelled.text);

  console.log('\n=== H. failure is visible ===');
  await page.evaluate(() => { window.__fail = 'webui.sh probe'; });
  await button('一键体检').click();
  await page.waitForTimeout(650);
  const failure = await page.evaluate(() => ({
    className: document.getElementById('result').className,
    text: document.getElementById('result').textContent
  }));
  check('failure result is red', failure.className.includes('err'));
  check('failure result says failed', failure.text.includes('失败'), failure.text);

  await page.screenshot({ path: path.join(outDir, 'v2.2.1-top.png') });
  check('no JavaScript exceptions', errors.length === 0, errors.join(' | '));

  console.log('\n================ RESULT ================');
  console.log('PASS=' + pass + '  FAIL=' + fail);
  await browser.close();
  process.exit(fail === 0 ? 0 : 1);
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
