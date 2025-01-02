<?php
namespace app\common\extend\upload;

class Btjson
{
    public $name = '图床服务';
    public $ver = '1.0';
    private $authCode;
    private $domain;
    private $serverCompress;
    private $uploadChannel;
    private $autoRetry;
    private $uploadNameType;
    private $returnFormat;

    public function __construct()
    {
        $config = $GLOBALS['config']['upload']['api']['btjson'];
        $this->authCode = $config['auth_code'];
        $this->domain = rtrim($config['domain'], '/');
        $this->serverCompress = $config['server_compress'] ?? true;
        $this->uploadChannel = $config['upload_channel'] ?? 'telegram';
        $this->autoRetry = $config['auto_retry'] ?? true;
        $this->uploadNameType = $config['upload_name_type'] ?? 'index';
        $this->returnFormat = $config['return_format'] ?? 'default';
    }

    public function submit($filePath)
    {
        $queryParams = [
            'authCode' => $this->authCode,
            'serverCompress' => $this->serverCompress ? 'true' : 'false',
            'uploadChannel' => $this->uploadChannel,
            'autoRetry' => $this->autoRetry ? 'true' : 'false',
            'uploadNameType' => $this->uploadNameType,
            'returnFormat' => $this->returnFormat
        ];
        
        $url = $this->domain . '/upload?' . http_build_query($queryParams);
        
        $postData = [
            'file' => new \CURLFile($filePath)
        ];

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $postData);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, FALSE);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, FALSE);

        $response = curl_exec($ch);

        if(curl_errno($ch)){
            throw new \Exception('Curl error: ' . curl_error($ch));
        }

        curl_close($ch);

        $jsonResponse = json_decode($response, true);

        if(isset($jsonResponse[0]['src'])) {
            unlink($filePath);
            return $this->domain . $jsonResponse[0]['src'];
        } else {
            throw new \Exception("Upload failed: " . $response);
        }
    }
}