<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Server Information</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.15.4/css/all.min.css">
    <link rel="icon" href="https://snyt.xyz/imgs/Logo256R.png" type="image/png">
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #121212;
            color: #ffffff;
        }
        .container {
            max-width: 800px;
            margin: auto;
            background-color: #212121;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 0 10px rgba(255, 255, 255, 0.1);
        }
        h1, h2 {
            color: #ffffff;
        }
        .section {
            margin-bottom: 30px;
        }
        .section h2 {
            font-size: 24px;
            margin-bottom: 10px;
            border-bottom: 2px solid #ffffff;
            padding-bottom: 5px;
        }
        .info p {
            margin: 5px 0;
        }
        .social-icons {
            margin-top: 20px;
        }
        .social-icons a {
            display: inline-flex;
            align-items: center;
            margin-right: 20px;
            color: #ffffff;
            text-decoration: none;
            font-size: 18px;
        }
        .social-icons a i {
            margin-right: 5px;
        }
        .social-icons a:hover {
            color: #007bff;
        }
        footer {
            margin-top: 20px;
            text-align: center;
            color: #999999;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Server Information</h1>

        <div class="section">
            <h2>Server Details</h2>
            <div class="info">
                <p><strong>Server Software:</strong> <?php echo $_SERVER['SERVER_SOFTWARE']; ?></p>
                <p><strong>Server Protocol:</strong> <?php echo $_SERVER['SERVER_PROTOCOL']; ?></p>
                <p><strong>Server Uptime:</strong> <?php echo shell_exec('uptime -p'); ?></p>
                <p><strong>CPU Cores:</strong> <?php echo shell_exec('nproc'); ?></p>
                <p><strong>Operating System:</strong> <?php echo php_uname('s'); ?></p>
            </div>
        </div>

        <div class="section">
            <h2>Disk Usage</h2>
            <div class="info">
                <p><strong>Total Disk Space:</strong> <?php echo shell_exec('df -h / | awk \'NR==2 {print $2}\''); ?></p>
                <p><strong>Used Disk Space:</strong> <?php echo shell_exec('df -h / | awk \'NR==2 {print $3}\''); ?></p>
                <p><strong>Free Disk Space:</strong> <?php echo shell_exec('df -h / | awk \'NR==2 {print $4}\''); ?></p>
            </div>
        </div>

        <div class="section">
            <h2>RAM Usage</h2>
            <div class="info">
                <?php
                $free = shell_exec('free -h');
                $free = (string)trim($free);
                $free_arr = explode("\n", $free);
                $mem = array_filter(explode(" ", $free_arr[1]));
                $mem = array_merge($mem);
                ?>
                <p><strong>Total RAM:</strong> <?php echo $mem[1]; ?></p>
                <p><strong>Used RAM:</strong> <?php echo $mem[2]; ?></p>
                <p><strong>Free RAM:</strong> <?php echo $mem[3]; ?></p>
            </div>
        </div>

        <div class="section">
            <h2>Connect with Me</h2>
            <div class="social-icons">
                <a href="https://twitter.com/ScarNaruto" class="twitter-button" target="_blank"><i class="fab fa-twitter"></i> Twitter</a>
                <a href="https://discord.snyt.xyz" class="discord-button" target="_blank"><i class="fab fa-discord"></i> Discord</a>
                <a href="http://example.com:61208" class="glances-button" target="_blank"><i class="fas fa-chart-line"></i> Open Glances</a>
                <a href="http://example.com:9000" class="phpmyadmin-button" target="_blank"><i class="fas fa-server"></i> Nginx UI</a>
            </div>
        </div>
    </div>
    <footer>
        &copy; 2024 ScarNaruto. All rights reserved.
    </footer>
</body>
</html>
