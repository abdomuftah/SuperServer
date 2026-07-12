<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SNYT SuperServer</title>
<style>
:root{color-scheme:dark}body{font-family:system-ui,-apple-system,sans-serif;background:#0b1020;color:#eef2ff;margin:0;padding:24px}.card{max-width:850px;margin:5vh auto;background:#141b2d;border:1px solid #29324a;border-radius:18px;padding:28px;box-shadow:0 20px 60px #0006}.badge{display:inline-block;padding:6px 10px;border-radius:999px;background:#223052;color:#b9d2ff}h1{margin:.5rem 0}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin-top:24px}.item{background:#0e1526;border-radius:12px;padding:15px}.k{color:#93a4c7;font-size:.82rem}.v{font-weight:700;margin-top:4px}a{color:#8fc7ff}footer{margin-top:24px;color:#8190ad;font-size:.9rem}
</style>
</head>
<body><main class="card">
<span class="badge">SNYT Hosting</span>
<h1>SuperServer is ready</h1>
<p>This server was provisioned successfully. Administrative credentials are stored locally and are not exposed on this page.</p>
<div class="grid">
<div class="item"><div class="k">Hostname</div><div class="v"><?=htmlspecialchars(gethostname() ?: 'Unknown',ENT_QUOTES,'UTF-8')?></div></div>
<div class="item"><div class="k">Web server</div><div class="v"><?=htmlspecialchars($_SERVER['SERVER_SOFTWARE'] ?? 'Unknown',ENT_QUOTES,'UTF-8')?></div></div>
<div class="item"><div class="k">PHP</div><div class="v"><?=htmlspecialchars(PHP_VERSION,ENT_QUOTES,'UTF-8')?></div></div>
<div class="item"><div class="k">phpMyAdmin</div><div class="v"><a href="/phpmyadmin">Open securely</a></div></div>
</div>
<footer>Powered by SNYT SuperServer</footer>
</main></body></html>
