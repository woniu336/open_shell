<?php
namespace app\common\extend\upload;

class Btjson
{
    public $name = '美团图床';
    public $ver = '1.0';
    private $token;
    private $clientId;

    public function __construct()
    {
        $this->token = $GLOBALS['config']['upload']['api']['btjson']['token'];
        $this->clientId = $GLOBALS['config']['upload']['api']['btjson']['client_id'];
    }

    public function submit($filePath)
    {
        $headers = $this->getHeaders();
        $postData = $this->buildPostData($filePath);

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, 'https://pic-up.meituan.com/extrastorage/new/video?isHttps=true');
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $postData);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, FALSE);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, FALSE);

        $response = curl_exec($ch);

        if(curl_errno($ch)){
            throw new \Exception('Curl error: ' . curl_error($ch));
        }

        curl_close($ch);

        $jsonResponse = json_decode($response, true);

        if(isset($jsonResponse['success']) && $jsonResponse['success'] === true) {
            unlink($filePath);
            return $jsonResponse['data']['originalLink'];
        } else {
            $errorMessage = isset($jsonResponse['error']['message']) ? $jsonResponse['error']['message'] : 'Unknown error';
            $errorCode = isset($jsonResponse['error']['code']) ? $jsonResponse['error']['code'] : 'Unknown code';
            $errorType = isset($jsonResponse['error']['type']) ? $jsonResponse['error']['type'] : 'Unknown type';
            throw new \Exception("Upload failed: Code: $errorCode, Type: $errorType, Message: $errorMessage");
        }
    }

    private function getHeaders()
    {
        return [
            'Accept: */*',
            'Accept-Encoding: gzip, deflate, br',
            'Accept-Language: zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
            'Cache-Control: no-cache',
            'Connection: keep-alive',
            'Content-Type: multipart/form-data; boundary=----WebKitFormBoundarywt1pMxJgab51elEB',
            'Host: pic-up.meituan.com',
            'Origin: https://czz.meituan.com',
            'Pragma: no-cache',
            'Referer: https://czz.meituan.com/',
            'Sec-Fetch-Dest: empty',
            'Sec-Fetch-Mode: cors',
            'Sec-Fetch-Site: same-site',
            'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.0.0',
            'client-id: ' . $this->clientId,
            'sec-ch-ua: "Not A(Brand";v="99", "Microsoft Edge";v="121", "Chromium";v="121"',
            'sec-ch-ua-mobile: ?0',
            'sec-ch-ua-platform: "Windows"',
            'token: ' . $this->token
        ];
    }

    private function buildPostData($filePath)
    {
        $file = new \CURLFile($filePath);
        $boundary = '----WebKitFormBoundarywt1pMxJgab51elEB';
        $postData = "--$boundary\r\n";
        $postData .= 'Content-Disposition: form-data; name="file"; filename="' . basename($filePath) . "\"\r\n";
        $postData .= 'Content-Type: ' . mime_content_type($filePath) . "\r\n\r\n";
        $postData .= file_get_contents($filePath) . "\r\n";
        $postData .= "--$boundary--\r\n";
        return $postData;
    }
}