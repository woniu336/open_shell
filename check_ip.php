<?php
/**
 * IP滥用检查系统 - 后端API
 * 使用AbuseIPDB API查询IP地址信息
 */

header('Content-Type: application/json; charset=utf-8');

// 配置你的AbuseIPDB API密钥
// 注册地址：https://www.abuseipdb.com/register
define('ABUSEIPDB_API_KEY', '你的API密钥'); // 请替换为你的API密钥

// 分类映射
$categoryMap = [
    3 => '欺诈订单',
    4 => 'DDoS攻击',
    5 => 'FTP暴力破解',
    6 => 'Ping死亡',
    7 => '钓鱼',
    8 => '欺诈VoIP',
    9 => '开放代理',
    10 => '垃圾邮件',
    11 => '扫描',
    12 => 'Botnet',
    13 => 'Web垃圾信息',
    14 => '电子邮件垃圾',
    15 => 'Blog垃圾',
    16 => 'VPN IP',
    18 => '暴力破解',
    19 => '恶意Web机器人',
    20 => 'Exploited主机',
    21 => 'Web应用攻击',
    22 => 'SSH攻击',
    23 => 'IoT目标',
];

// 检查是否为POST请求
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode([
        'success' => false,
        'message' => '只支持POST请求'
    ]);
    exit;
}

// 获取IP地址
$ip = isset($_POST['ip']) ? trim($_POST['ip']) : '';

// 验证IP地址
if (empty($ip)) {
    echo json_encode([
        'success' => false,
        'message' => '请输入IP地址'
    ]);
    exit;
}

if (!filter_var($ip, FILTER_VALIDATE_IP)) {
    echo json_encode([
        'success' => false,
        'message' => 'IP地址格式不正确'
    ]);
    exit;
}

// 检查API密钥是否配置
if (ABUSEIPDB_API_KEY === 'YOUR_API_KEY_HERE') {
    echo json_encode([
        'success' => false,
        'message' => '请先配置AbuseIPDB API密钥'
    ]);
    exit;
}

// 调用AbuseIPDB API
try {
    $url = 'https://api.abuseipdb.com/api/v2/check';
    $queryString = http_build_query([
        'ipAddress' => $ip,
        'maxAgeInDays' => '90',
        'verbose' => ''
    ]);

    $curl = curl_init();
    curl_setopt_array($curl, [
        CURLOPT_URL => $url . '?' . $queryString,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_ENCODING => '',
        CURLOPT_MAXREDIRS => 10,
        CURLOPT_TIMEOUT => 30,
        CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
        CURLOPT_CUSTOMREQUEST => 'GET',
        CURLOPT_HTTPHEADER => [
            'Key: ' . ABUSEIPDB_API_KEY,
            'Accept: application/json',
        ],
    ]);

    $response = curl_exec($curl);
    $httpCode = curl_getinfo($curl, CURLINFO_HTTP_CODE);
    $err = curl_error($curl);
    curl_close($curl);

    if ($err) {
        throw new Exception('请求错误: ' . $err);
    }

    if ($httpCode !== 200) {
        throw new Exception('API返回错误状态码: ' . $httpCode);
    }

    $data = json_decode($response, true);

    if (!isset($data['data'])) {
        throw new Exception('API返回数据格式错误');
    }

    $ipData = $data['data'];

    // 处理分类
    $categories = [];
    if (!empty($ipData['reports'])) {
        $categoryIds = [];
        foreach ($ipData['reports'] as $report) {
            if (!empty($report['categories'])) {
                $categoryIds = array_merge($categoryIds, $report['categories']);
            }
        }
        $categoryIds = array_unique($categoryIds);
        foreach ($categoryIds as $catId) {
            if (isset($categoryMap[$catId])) {
                $categories[] = $categoryMap[$catId];
            }
        }
    }

    // 处理报告摘要（取最近3条）
    $reports = [];
    if (!empty($ipData['reports'])) {
        $recentReports = array_slice($ipData['reports'], 0, 3);
        foreach ($recentReports as $report) {
            $reports[] = [
                'country' => $report['reporterCountryName'] ?? '未知',
                'time' => formatTime($report['reportedAt'] ?? ''),
                'comment' => mb_substr($report['comment'] ?? '无评论', 0, 100) . '...'
            ];
        }
    }

    // 检查是否有最近一周的报告
    $hasRecentReports = false;
    if (!empty($ipData['lastReportedAt'])) {
        $lastReportTime = strtotime($ipData['lastReportedAt']);
        $oneWeekAgo = time() - (7 * 24 * 60 * 60);
        $hasRecentReports = $lastReportTime > $oneWeekAgo;
    }

    // 返回处理后的数据
    echo json_encode([
        'success' => true,
        'data' => [
            'ipAddress' => $ipData['ipAddress'],
            'abuseConfidenceScore' => $ipData['abuseConfidenceScore'],
            'totalReports' => $ipData['totalReports'],
            'numDistinctUsers' => $ipData['numDistinctUsers'],
            'isp' => $ipData['isp'] ?? '未知',
            'usageType' => $ipData['usageType'] ?? '未知',
            'asn' => $ipData['domain'] ? 'AS' . $ipData['domain'] : '未知',
            'country' => $ipData['countryName'] ?? '未知',
            'city' => $ipData['city'] ?? '',
            'domain' => $ipData['domain'] ?? '未知',
            'hostname' => !empty($ipData['hostnames']) ? implode(', ', $ipData['hostnames']) : '未知',
            'categories' => $categories,
            'reports' => $reports,
            'hasRecentReports' => $hasRecentReports,
            'lastReportedAt' => $ipData['lastReportedAt'] ?? null
        ]
    ], JSON_UNESCAPED_UNICODE);

} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'message' => '查询失败: ' . $e->getMessage()
    ], JSON_UNESCAPED_UNICODE);
}

/**
 * 格式化时间显示
 */
function formatTime($datetime) {
    if (empty($datetime)) {
        return '未知';
    }
    
    $timestamp = strtotime($datetime);
    $diff = time() - $timestamp;
    
    if ($diff < 3600) {
        return floor($diff / 60) . '分钟前';
    } elseif ($diff < 86400) {
        return floor($diff / 3600) . '小时前';
    } elseif ($diff < 2592000) {
        return floor($diff / 86400) . '天前';
    } else {
        return date('Y-m-d', $timestamp);
    }
}
?>