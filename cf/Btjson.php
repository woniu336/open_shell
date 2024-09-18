<?php
namespace app\common\extend\upload;

class Btjson
{
    public $name = 'Cloudflare R2存储';
    public $ver = '1.0';
    private $accessKey;
    private $secretKey;
    private $endpoint;
    private $customDomain;
    private $bucketName;
    private $region = 'us-east-1';  // 使用具体的region，而不是'auto'
    private $uploadPathTemplate;

    public function __construct()
    {
        $this->accessKey = $GLOBALS['config']['upload']['api']['btjson']['access_key'];
        $this->secretKey = $GLOBALS['config']['upload']['api']['btjson']['secret_key'];
        $this->endpoint = $GLOBALS['config']['upload']['api']['btjson']['endpoint'];
        $this->customDomain = $GLOBALS['config']['upload']['api']['btjson']['custom_domain'] ?? null;
        $this->bucketName = $GLOBALS['config']['upload']['api']['btjson']['bucket_name'];
        $this->uploadPathTemplate = $GLOBALS['config']['upload']['api']['btjson']['upload_path_template'] ?? 'img/%y/%mo/%d';
    }

    public function submit($filePath)
    {
        $this->log("Starting upload for file: " . $filePath);
        
        $key = $this->generateUploadPath($filePath);
        $endpoint = preg_replace('#^https?://#', '', $this->endpoint);
        $url = "https://{$endpoint}/{$this->bucketName}/{$key}";

        $dateTime = new \DateTime('UTC');
        $amzDate = $dateTime->format('Ymd\THis\Z');
        $dateStamp = $dateTime->format('Ymd');

        $headers = [
            'host' => $endpoint,
            'x-amz-date' => $amzDate,
            'x-amz-content-sha256' => hash_file('sha256', $filePath),
        ];

        $signedHeaders = $this->getSignedHeaders($headers);
        $canonicalUri = "/{$this->bucketName}/{$key}";
        $canonicalRequest = $this->getCanonicalRequest('PUT', $canonicalUri, '', $headers, $signedHeaders, hash_file('sha256', $filePath));
        $stringToSign = $this->getStringToSign($amzDate, $this->region, $canonicalRequest);
        $signature = $this->calculateSignature($dateStamp, $this->region, $stringToSign);

        $authorization = $this->getAuthorizationHeader($dateStamp, $this->region, $signedHeaders, $signature);

        $headers['Authorization'] = $authorization;

        $this->log("Prepared headers", $headers);
        $this->log("Canonical Request", $canonicalRequest);
        $this->log("String to Sign", $stringToSign);
        $this->log("Signature", $signature);

        $curlHeaders = [];
        foreach ($headers as $key => $value) {
            $curlHeaders[] = "{$key}: {$value}";
        }

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_PUT, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $curlHeaders);
        curl_setopt($ch, CURLOPT_INFILE, fopen($filePath, 'r'));
        curl_setopt($ch, CURLOPT_INFILESIZE, filesize($filePath));
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        curl_setopt($ch, CURLOPT_VERBOSE, true);

        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);

        $this->log("cURL response", [
            'httpCode' => $httpCode,
            'response' => $response,
            'curlError' => curl_error($ch)
        ]);

        if(curl_errno($ch)){
            $error = curl_error($ch);
            curl_close($ch);
            $this->log("Curl error", $error);
            throw new \Exception("Curl error: {$error}\nURL: {$url}\nEndpoint: {$endpoint}");
        }

        curl_close($ch);

        if($httpCode == 200) {
            unlink($filePath);
            $this->log("Upload successful", $url);
            return $url;
        } else {
            $debugInfo = "URL: {$url}\nEndpoint: {$endpoint}\n";
            $debugInfo .= "Headers: " . print_r($curlHeaders, true) . "\n";
            $debugInfo .= "CanonicalRequest: {$canonicalRequest}\n";
            $debugInfo .= "StringToSign: {$stringToSign}\n";
            $debugInfo .= "Signature: {$signature}\n";
            $this->log("Upload failed", $debugInfo);
            throw new \Exception("Upload failed: HTTP code {$httpCode}, Response: {$response}\n{$debugInfo}");
        }
    }

    public function testConnection()
    {
        $this->log("Testing connection");
        
        $dateTime = new \DateTime('UTC');
        $amzDate = $dateTime->format('Ymd\THis\Z');
        $dateStamp = $dateTime->format('Ymd');

        $endpoint = preg_replace('#^https?://#', '', $this->endpoint);
        $headers = [
            'host' => $endpoint,
            'x-amz-date' => $amzDate,
        ];

        $signedHeaders = $this->getSignedHeaders($headers);
        $canonicalUri = "/{$this->bucketName}/";
        $canonicalRequest = $this->getCanonicalRequest('GET', $canonicalUri, '', $headers, $signedHeaders, 'UNSIGNED-PAYLOAD');
        $stringToSign = $this->getStringToSign($amzDate, $this->region, $canonicalRequest);
        $signature = $this->calculateSignature($dateStamp, $this->region, $stringToSign);

        $authorization = $this->getAuthorizationHeader($dateStamp, $this->region, $signedHeaders, $signature);

        $headers['Authorization'] = $authorization;

        $curlHeaders = [];
        foreach ($headers as $key => $value) {
            $curlHeaders[] = "{$key}: {$value}";
        }

        $ch = curl_init();
        $url = "https://{$endpoint}/{$this->bucketName}/";
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $curlHeaders);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        curl_setopt($ch, CURLOPT_VERBOSE, true);

        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);

        $this->log("Test connection response", [
            'url' => $url,
            'httpCode' => $httpCode,
            'response' => $response,
            'curlError' => curl_error($ch)
        ]);

        curl_close($ch);

        return $httpCode == 200;
    }

    private function getSignedHeaders($headers)
    {
        ksort($headers);
        return implode(';', array_keys($headers));
    }

    private function getCanonicalRequest($method, $uri, $queryString, $headers, $signedHeaders, $payload)
    {
        $canonicalHeaders = '';
        ksort($headers);
        foreach ($headers as $key => $value) {
            $canonicalHeaders .= strtolower($key) . ':' . trim($value) . "\n";
        }

        return implode("\n", [
            $method,
            $uri,
            $queryString,
            $canonicalHeaders,
            $signedHeaders,
            $payload
        ]);
    }

    private function getStringToSign($amzDate, $region, $canonicalRequest)
    {
        $algorithm = 'AWS4-HMAC-SHA256';
        $scope = substr($amzDate, 0, 8) . "/{$region}/s3/aws4_request";
        return implode("\n", [
            $algorithm,
            $amzDate,
            $scope,
            hash('sha256', $canonicalRequest)
        ]);
    }

    private function calculateSignature($dateStamp, $region, $stringToSign)
    {
        $kSecret = 'AWS4' . $this->secretKey;
        $kDate = hash_hmac('sha256', $dateStamp, $kSecret, true);
        $kRegion = hash_hmac('sha256', $region, $kDate, true);
        $kService = hash_hmac('sha256', 's3', $kRegion, true);
        $kSigning = hash_hmac('sha256', 'aws4_request', $kService, true);
        return hash_hmac('sha256', $stringToSign, $kSigning);
    }

    private function getAuthorizationHeader($dateStamp, $region, $signedHeaders, $signature)
    {
        $algorithm = 'AWS4-HMAC-SHA256';
        $scope = "{$dateStamp}/{$region}/s3/aws4_request";
        return "{$algorithm} Credential={$this->accessKey}/{$scope}, SignedHeaders={$signedHeaders}, Signature={$signature}";
    }

    private function generateUploadPath($filePath)
    {
        $dateTime = new \DateTime('UTC');
        $year = $dateTime->format('Y');
        $month = $dateTime->format('m');
        $day = $dateTime->format('d');

        $uploadPath = str_replace('%y', $year, $this->uploadPathTemplate);
        $uploadPath = str_replace('%mo', $month, $uploadPath);
        $uploadPath = str_replace('%d', $day, $uploadPath);

        $fileName = basename($filePath);
        return $uploadPath . '/' . $fileName;
    }

    private function log($message, $data = null)
    {
        $logMessage = date('Y-m-d H:i:s') . " - " . $message;
        if ($data !== null) {
            $logMessage .= "\n" . print_r($data, true);
        }
        file_put_contents(__DIR__ . '/upload_debug.log', $logMessage . "\n\n", FILE_APPEND);
    }
}