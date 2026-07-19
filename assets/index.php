<?php
declare(strict_types=1);

$configuredDomain = 'example.com';
$primaryDomain = 'primary.example.com';
$configuredPhp = 'phpversion';

function h(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function formatBytes(float $bytes): string
{
    $units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    $index = 0;
    while ($bytes >= 1024 && $index < count($units) - 1) {
        $bytes /= 1024;
        $index++;
    }
    return number_format($bytes, $index === 0 ? 0 : 1) . ' ' . $units[$index];
}

function readOsName(): string
{
    $file = '/etc/os-release';
    if (!is_readable($file)) {
        return php_uname('s') . ' ' . php_uname('r');
    }

    foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        if (str_starts_with($line, 'PRETTY_NAME=')) {
            return trim(substr($line, 12), "\"'");
        }
    }
    return php_uname('s') . ' ' . php_uname('r');
}

function memoryStats(): array
{
    $values = [];
    if (is_readable('/proc/meminfo')) {
        foreach (file('/proc/meminfo', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
            if (preg_match('/^([A-Za-z_()]+):\s+(\d+)\s+kB$/', $line, $match)) {
                $values[$match[1]] = (int) $match[2] * 1024;
            }
        }
    }

    $total = (float) ($values['MemTotal'] ?? 0);
    $available = (float) ($values['MemAvailable'] ?? 0);
    $used = max(0, $total - $available);
    $percent = $total > 0 ? ($used / $total) * 100 : 0;

    return [$used, $total, $percent];
}

function uptimeText(): string
{
    if (!is_readable('/proc/uptime')) {
        return 'Unavailable';
    }

    $seconds = (int) floor((float) explode(' ', trim((string) file_get_contents('/proc/uptime')))[0]);
    $days = intdiv($seconds, 86400);
    $hours = intdiv($seconds % 86400, 3600);
    $minutes = intdiv($seconds % 3600, 60);

    $parts = [];
    if ($days > 0) $parts[] = $days . 'd';
    if ($hours > 0 || $days > 0) $parts[] = $hours . 'h';
    $parts[] = $minutes . 'm';
    return implode(' ', $parts);
}

$hostname = gethostname() ?: 'Unknown';
$host = preg_replace('/:\d+$/', '', $_SERVER['HTTP_HOST'] ?? $configuredDomain) ?: $configuredDomain;
$serverSoftware = $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown';
$phpVersion = PHP_VERSION;
$sapi = PHP_SAPI;
$osName = readOsName();
$load = function_exists('sys_getloadavg') ? (sys_getloadavg() ?: [0, 0, 0]) : [0, 0, 0];
[$memoryUsed, $memoryTotal, $memoryPercent] = memoryStats();
$diskTotal = (float) (disk_total_space('/') ?: 0);
$diskFree = (float) (disk_free_space('/') ?: 0);
$diskUsed = max(0, $diskTotal - $diskFree);
$diskPercent = $diskTotal > 0 ? ($diskUsed / $diskTotal) * 100 : 0;
$isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || (int) ($_SERVER['SERVER_PORT'] ?? 0) === 443;
$isPrimary = strcasecmp($host, $primaryDomain) === 0;
$primaryUrl = '//' . $primaryDomain;
$documentRoot = $_SERVER['DOCUMENT_ROOT'] ?? ('/var/www/html/' . $configuredDomain);
$extensions = count(get_loaded_extensions());
$time = date('D, d M Y • H:i T');
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex,nofollow">
    <title><?= h($host) ?> • SNYT SuperServer</title>
    <style>
        :root {
            color-scheme: dark;
            --bg: #070a12;
            --panel: rgba(16, 22, 38, .76);
            --panel-strong: rgba(21, 29, 49, .94);
            --line: rgba(255, 255, 255, .09);
            --text: #f4f7ff;
            --muted: #96a1bd;
            --blue: #5da9ff;
            --cyan: #4de2d1;
            --green: #70eda8;
            --purple: #a985ff;
            --shadow: 0 30px 100px rgba(0, 0, 0, .48);
            font-family: Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            min-height: 100vh;
            color: var(--text);
            background:
                radial-gradient(circle at 8% 0%, rgba(93,169,255,.20), transparent 34%),
                radial-gradient(circle at 92% 8%, rgba(169,133,255,.18), transparent 30%),
                radial-gradient(circle at 50% 105%, rgba(77,226,209,.12), transparent 38%),
                var(--bg);
            padding: 28px;
        }
        body::before {
            content: "";
            position: fixed;
            inset: 0;
            pointer-events: none;
            opacity: .22;
            background-image: linear-gradient(rgba(255,255,255,.025) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,.025) 1px, transparent 1px);
            background-size: 42px 42px;
            mask-image: linear-gradient(to bottom, black, transparent 80%);
        }
        .wrap { width: min(1180px, 100%); margin: 0 auto; position: relative; }
        .topbar { display: flex; align-items: center; justify-content: space-between; gap: 18px; margin-bottom: 26px; }
        .brand { display: flex; align-items: center; gap: 13px; font-weight: 900; letter-spacing: .08em; }
        .logo { width: 42px; height: 42px; display: grid; place-items: center; border-radius: 14px; background: linear-gradient(135deg, var(--blue), var(--purple)); box-shadow: 0 14px 35px rgba(93,169,255,.25); }
        .logo svg { width: 23px; height: 23px; }
        .status { display: inline-flex; align-items: center; gap: 9px; padding: 9px 13px; border: 1px solid rgba(112,237,168,.22); border-radius: 999px; background: rgba(112,237,168,.08); color: #bdf8d5; font-size: .86rem; font-weight: 750; }
        .status i { width: 9px; height: 9px; border-radius: 50%; background: var(--green); box-shadow: 0 0 18px var(--green); }
        .hero { position: relative; overflow: hidden; padding: clamp(28px, 5vw, 60px); border: 1px solid var(--line); border-radius: 30px; background: linear-gradient(145deg, rgba(25,34,58,.91), rgba(11,15,27,.82)); box-shadow: var(--shadow); }
        .hero::after { content: ""; position: absolute; width: 330px; height: 330px; right: -100px; top: -150px; border-radius: 50%; background: radial-gradient(circle, rgba(93,169,255,.28), transparent 66%); }
        .eyebrow { color: var(--cyan); font-size: .8rem; font-weight: 850; letter-spacing: .14em; text-transform: uppercase; }
        h1 { max-width: 820px; margin: 15px 0 16px; font-size: clamp(2.5rem, 7vw, 5.7rem); line-height: .95; letter-spacing: -.055em; }
        .gradient { background: linear-gradient(90deg, #fff, #a9ccff 46%, #c7b4ff); -webkit-background-clip: text; color: transparent; }
        .lead { max-width: 740px; color: #b8c2db; font-size: clamp(1rem, 2vw, 1.16rem); line-height: 1.75; }
        .actions { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 28px; }
        .button { display: inline-flex; align-items: center; gap: 9px; padding: 13px 17px; border-radius: 13px; text-decoration: none; font-weight: 850; transition: transform .18s ease, border-color .18s ease; }
        .button:hover { transform: translateY(-2px); }
        .primary { background: linear-gradient(135deg, var(--blue), #8d78ff); color: white; box-shadow: 0 14px 30px rgba(93,169,255,.22); }
        .secondary { color: #dce5fa; border: 1px solid var(--line); background: rgba(255,255,255,.045); }
        .grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 14px; margin-top: 18px; }
        .card { min-height: 145px; padding: 20px; border: 1px solid var(--line); border-radius: 20px; background: var(--panel); backdrop-filter: blur(18px); }
        .card .label { color: var(--muted); font-size: .74rem; font-weight: 800; letter-spacing: .11em; text-transform: uppercase; }
        .card .value { margin-top: 12px; font-size: 1.12rem; font-weight: 850; overflow-wrap: anywhere; }
        .card .sub { margin-top: 8px; color: #7f8ba8; font-size: .83rem; line-height: 1.45; }
        .meter { height: 7px; margin-top: 16px; overflow: hidden; border-radius: 999px; background: rgba(255,255,255,.07); }
        .meter span { display: block; height: 100%; border-radius: inherit; background: linear-gradient(90deg, var(--cyan), var(--blue), var(--purple)); }
        .details { display: grid; grid-template-columns: 1.15fr .85fr; gap: 18px; margin-top: 18px; }
        .panel { padding: 24px; border: 1px solid var(--line); border-radius: 22px; background: var(--panel-strong); }
        .panel h2 { margin: 0 0 18px; font-size: 1.05rem; }
        .rows { display: grid; gap: 1px; overflow: hidden; border-radius: 14px; background: var(--line); }
        .row { display: grid; grid-template-columns: 160px 1fr; gap: 14px; padding: 13px 15px; background: #111729; }
        .row span:first-child { color: var(--muted); }
        .row span:last-child { text-align: right; font-weight: 700; overflow-wrap: anywhere; }
        code { color: #c6d8ff; font-family: "SFMono-Regular", Consolas, monospace; font-size: .9em; }
        .notice { color: #9da9c4; line-height: 1.7; }
        .notice strong { color: #eff4ff; }
        footer { display: flex; justify-content: space-between; flex-wrap: wrap; gap: 10px; padding: 24px 5px 5px; color: #6f7b98; font-size: .83rem; }
        @media (max-width: 900px) { .grid { grid-template-columns: repeat(2, 1fr); } .details { grid-template-columns: 1fr; } }
        @media (max-width: 560px) { body { padding: 15px; } .topbar { align-items: flex-start; } .grid { grid-template-columns: 1fr; } .hero { border-radius: 23px; } .row { grid-template-columns: 1fr; gap: 5px; } .row span:last-child { text-align: left; } }
    </style>
</head>
<body>
<div class="wrap">
    <header class="topbar">
        <div class="brand">
            <span class="logo" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none"><path d="M5 6.5h14M5 12h9M5 17.5h14" stroke="white" stroke-width="2.2" stroke-linecap="round"/></svg></span>
            <span>SNYT HOSTING</span>
        </div>
        <span class="status"><i></i> Server online</span>
    </header>

    <main>
        <section class="hero">
            <div class="eyebrow">SNYT SuperServer • <?= h($host) ?></div>
            <h1><span class="gradient">Your web stack is ready.</span></h1>
            <p class="lead">This domain is running through a validated PHP-FPM stack. Replace this page with your application when you are ready to deploy.</p>
            <div class="actions">
                <?php if ($isPrimary): ?>
                    <a class="button primary" href="/phpmyadmin/">Open phpMyAdmin →</a>
                <?php else: ?>
                    <a class="button primary" href="<?= h($primaryUrl) ?>">Open primary server →</a>
                <?php endif; ?>
                <a class="button secondary" href="https://github.com/abdomuftah/SuperServer" rel="noreferrer">SuperServer project</a>
            </div>
        </section>

        <section class="grid" aria-label="Server overview">
            <article class="card"><div class="label">PHP Runtime</div><div class="value">PHP <?= h($phpVersion) ?></div><div class="sub"><?= h($sapi) ?> • <?= $extensions ?> loaded extensions</div></article>
            <article class="card"><div class="label">Memory</div><div class="value"><?= h(formatBytes($memoryUsed)) ?> / <?= h(formatBytes($memoryTotal)) ?></div><div class="sub"><?= number_format($memoryPercent, 1) ?>% currently used</div><div class="meter"><span style="width:<?= min(100, max(0, $memoryPercent)) ?>%"></span></div></article>
            <article class="card"><div class="label">Root Disk</div><div class="value"><?= h(formatBytes($diskUsed)) ?> / <?= h(formatBytes($diskTotal)) ?></div><div class="sub"><?= number_format($diskPercent, 1) ?>% currently used</div><div class="meter"><span style="width:<?= min(100, max(0, $diskPercent)) ?>%"></span></div></article>
            <article class="card"><div class="label">System Load</div><div class="value"><?= number_format((float) $load[0], 2) ?></div><div class="sub">1m / 5m / 15m: <?= implode(' • ', array_map(static fn($v) => number_format((float) $v, 2), $load)) ?></div></article>
        </section>

        <section class="details">
            <article class="panel">
                <h2>Runtime details</h2>
                <div class="rows">
                    <div class="row"><span>Domain</span><span><?= h($host) ?></span></div>
                    <div class="row"><span>Hostname</span><span><?= h($hostname) ?></span></div>
                    <div class="row"><span>Operating system</span><span><?= h($osName) ?></span></div>
                    <div class="row"><span>Web server</span><span><?= h($serverSoftware) ?></span></div>
                    <div class="row"><span>Connection</span><span><?= $isHttps ? 'HTTPS secured' : 'HTTP — SSL pending' ?></span></div>
                    <div class="row"><span>Uptime</span><span><?= h(uptimeText()) ?></span></div>
                    <div class="row"><span>Server time</span><span><?= h($time) ?></span></div>
                </div>
            </article>

            <aside class="panel">
                <h2>Deployment notes</h2>
                <p class="notice"><strong>Document root</strong><br><code><?= h($documentRoot) ?></code></p>
                <p class="notice"><strong>Add another domain</strong><br><code>super-sdomain</code></p>
                <p class="notice"><strong>Credentials</strong><br><code>/root/SNYT/serverInfo.txt</code></p>
                <p class="notice"><strong>Installation log</strong><br><code>/var/log/snyt-superserver.log</code></p>
                <p class="notice">Sensitive credentials are never displayed on this page.</p>
            </aside>
        </section>
    </main>

    <footer><span>Powered by SNYT SuperServer</span><span>Configured PHP target: <?= h($configuredPhp) ?></span></footer>
</div>
</body>
</html>
