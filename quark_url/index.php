<?php
require_once '/www/wwwroot/123.org/check_link/LinkChecker.php';
use eking\netdisk\LinkChecker;

header('Content-Type: application/json');

if (isset($_GET['url'])) {
    $url = $_GET['url'];
    $linkChecker = new LinkChecker();
    $isValid = $linkChecker->checkUrl($url);
    
    echo json_encode(['valid' => $isValid]);
} else {
    echo json_encode(['error' => 'No URL provided']);
}