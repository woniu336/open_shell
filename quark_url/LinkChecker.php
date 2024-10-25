<?php
namespace eking\netdisk;

class LinkChecker
{
    const VERSION = "1.0.1";

    protected $url = '';

    public function __construct()
    {
        // 初始化操作，如果需要的话
    }
    
    /**
     * 发送 HTTP GET 请求
     *
     * @param string $url 请求的 URL
     * @param array $headers 请求头
     * @return array 包含响应码、响应头、响应体和错误信息的数组
     */
    protected function get($url, $headers = [])
    {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HEADER, true);
        if (!empty($headers)) {
            curl_setopt($ch, CURLOPT_HTTPHEADER, array_merge(array_map(function ($k, $v) {
                return "$k: $v";
            }, array_keys($headers), $headers), ['Content-Type: application/json']));
        }
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);

        $response = curl_exec($ch);

        if (curl_errno($ch)) {
            $error_msg = curl_error($ch);
            curl_close($ch);
            return [null, null, null, $error_msg];
        }

        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $headerSize = curl_getinfo($ch, CURLINFO_HEADER_SIZE);
        $responseHeader = substr($response, 0, $headerSize);
        $responseBody = substr($response, $headerSize);

        curl_close($ch);

        return [$httpCode, $responseHeader, $responseBody, null];
    }

    /**
     * 发送 HTTP POST 请求
     *
     * @param string $url 请求的 URL
     * @param array $headers 请求头
     * @param array $data 请求体
     * @return array 包含响应码、响应头、响应体和错误信息的数组
     */
    protected function post($url, $headers, $data)
    {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HEADER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        if (!empty($data)) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
        }
        if (!empty($headers)) {
            curl_setopt($ch, CURLOPT_HTTPHEADER, array_merge(array_map(function ($k, $v) {
                return "$k: $v";
            }, array_keys($headers), $headers), ['Content-Type: application/json']));
        }
        curl_setopt($ch, CURLOPT_FOLLOWLOCATION, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);

        $response = curl_exec($ch);
        $error = curl_error($ch);
        
        if ($error) {
            return [null, null, null, $error];
        }

        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $headerSize = curl_getinfo($ch, CURLINFO_HEADER_SIZE);
        $responseHeader = substr($response, 0, $headerSize);
        $responseBody = substr($response, $headerSize);
        curl_close($ch);

        return [$httpCode, $responseHeader, $responseBody, null];
    }

    /**
     * 检查阿里云盘分享链接是否有效
     *
     * @param string $url 阿里云盘分享链接
     * @return bool 如果链接有效，返回 true；否则返回 false
     */
    protected function aliYunCheck($url)
    {
        $share_id = substr($url, strpos($url, '/s/') + 3);
        $api_url = "https://api.alipan.com/v2/share_link/get_share_by_anonymous";
        $headers = [
            "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
            "Referer: https://www.alipan.com/",
            "Content-Type: application/json"
        ];
        $data = json_encode(["share_id" => $share_id]);
        list($code, $header, $body, $error) = $this->post($api_url, $headers, $data);
        $responseData = json_decode($body);
        // 检查响应数据
        if ($responseData && isset($responseData->share_name)) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * 检查夸克网盘分享链接是否有效
     *
     * @param string $url 夸克网盘分享链接
     * @return bool 如果链接有效，返回 true；否则返回 false
     */
    protected function quarkCheck($url)
    {
        preg_match('/https:\/\/pan\.quark\.cn\/s\/(\w+)[\?]?/', $url, $matches);
        if (!$matches) {
            return false;
        }
        $pwd_id = $matches[1];

        $apiUrl = "https://pan.quark.cn/1/clouddrive/share/sharepage/token";
        $headers = [
            'Referer: https://pan.quark.cn',
        ];
        $data = json_encode(['pwd_id' => $pwd_id]);

        list($code, $header, $body, $error) = $this->post($apiUrl, $headers, $data);

        if ($body) {
            $r = json_decode($body, true);
            if ($r['code'] == 0 && $r['message'] == 'ok') {
                return true;
            }
        }
        return false;
    }

    /**
     * 检查百度云盘分享链接是否有效
     *
     * @param string $url 百度云盘分享链接
     * @return bool 如果链接有效，返回 true；否则返回 false
     */
    protected function baiduYunCheck($url)
    {
        $headers = [
            "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1 Edg/94.0.4606.81",
        ];

        list($code, $header, $body, $error) = $this->get($url, $headers);

        if (!preg_match('/Location: (.*)/', $header, $matches)) {
            return false;
        }

        $locationUrl = trim($matches[1]);
        $errorIndex = strpos($locationUrl, "error");
        return $errorIndex === false;
    }

    /**
     * 检查 115 网盘分享链接是否有效
     *
     * @param string $url 115 网盘分享链接
     * @return bool 如果链接有效，返回 true；否则返回 false
     */
    protected function d115check($url)
    {
        $url = "https://webapi.115.com/share/snap?share_code=" . substr($url, 18, 11);
        list($code, $header, $body, $error) = $this->get($url, []);
        if ($body === null) {
            return false;
        }
        $errorIndex = strpos($body, '"errno":4100012');
        return $errorIndex !== false;
    }

    /**
     * 检查给定的URL是否属于支持的云存储服务，并调用相应的检查方法
     *
     * @param string $url 要检查的URL
     * @return bool 如果URL属于支持的云存储服务并且有效，则返回true；否则返回false
     */
    public function checkUrl($url)
    {
        if (strpos($url, 'alipan.com') !== false || strpos($url, 'alipan.com') !== false) {
            return $this->aliYunCheck($url);
        } elseif (strpos($url, '115.com') !== false) {
            return $this->d115check($url);
        } elseif (strpos($url, 'quark.cn') !== false) {
            return $this->quarkCheck($url);
        } elseif (strpos($url, 'baidu.com') !== false) {
            return $this->baiduYunCheck($url);
        } else {
            return false;
        }
    }
}