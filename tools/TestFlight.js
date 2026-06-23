/**
 * TestFlight 监控 (Surge 优化版)
 * 监控 TestFlight 名额，仅在「满 → 有名额」时通知一次，避免重复轰炸
 *
 * [Script] 段配置示例：
 *   TestFlight = type=cron,cronexp="*/5 * * * *",timeout=30,script-path=TestFlight_Surge.js,argument=hmC52rdF,b6X29Sva
 *
 * argument：要监控的 TestFlight ID，多个用英文逗号分隔
 *   支持备注：ID#备注名   例如  hmC52rdF#某APP
 * 注意：多 ID 监控请把 timeout 调大（如 30），默认 5 秒可能不够
 */

const UA_LIST = [
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 11_6_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 12_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36",
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
];
const randomUA = () => UA_LIST[Math.floor(Math.random() * UA_LIST.length)];

// 状态正则
const RE_FULL = /版本的测试员已满|This beta is full|此 beta 版已额满/;
const RE_CLOSED = /版本目前不接受任何新测试员|This beta isn't accepting any new testers/;
const RE_OPEN = /要加入 Beta 版|To join the|开始测试|itms-beta:\/\/|join the beta/;

function main() {
  const raw = (typeof $argument !== "undefined" && $argument) ? $argument.trim() : "";
  if (!raw) {
    console.log("[TF] 未配置 argument，请在脚本配置行填入 TestFlight ID");
    return $done();
  }

  const ids = raw.split(/\s*[,，;\n]\s*/).filter(Boolean);
  console.log(`[TF] 开始检查 ${ids.length} 个: ${ids.join(", ")}`);

  let pending = ids.length;
  const done = () => { if (--pending <= 0) $done(); };

  ids.forEach((info) => {
    let id = info, name = "";
    if (info.includes("#")) {
      const parts = info.split("#");
      id = parts[0].trim();
      name = parts[1].trim();
    }

    const url = `https://testflight.apple.com/join/${id}`;
    const storeKey = `tf_state_${id}`;

    $httpClient.get(
      { url, headers: { "User-Agent": randomUA() }, timeout: 10 },
      (err, resp, data) => {
        if (err) {
          console.log(`[!] ${info} → 请求失败: ${err}`);
          return done();
        }
        if (resp.status === 404) {
          console.log(`[D] ${info} → 链接不存在`);
          $persistentStore.write("invalid", storeKey);
          return done();
        }
        if (resp.status !== 200) {
          console.log(`[?] ${info} → HTTP ${resp.status}`);
          return done();
        }

        const last = $persistentStore.read(storeKey);

        if (RE_FULL.test(data)) {
          console.log(`[F] ${info} → 已满`);
          $persistentStore.write("full", storeKey);
        } else if (RE_CLOSED.test(data)) {
          console.log(`[N] ${info} → 暂不接受新成员`);
          $persistentStore.write("closed", storeKey);
        } else if (RE_OPEN.test(data)) {
          // 仅在状态变化时通知，避免重复轰炸
          if (last !== "open") {
            console.log(`[Y] ${info} → 可加入 ✅ 发送通知`);
            $notification.post(
              "🎉 TestFlight 有名额了！",
              name ? `${name} (${id})` : `ID: ${id}`,
              "点击立即加入测试",
              { action: "open-url", url: url, sound: true }
            );
          } else {
            console.log(`[Y] ${info} → 仍有名额（已通知过，跳过）`);
          }
          $persistentStore.write("open", storeKey);
        } else {
          console.log(`[?] ${info} → 状态未知`);
        }
        done();
      }
    );
  });
}

main();
