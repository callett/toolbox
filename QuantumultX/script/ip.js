if ($response.statusCode != 200) {
    $done(null);
}

const emojis = ["🆘","🈲","⚠️","🔞","📵","🚦","🏖","🖥","📺","🐧","🐬","🦉","🍄","⛳️","🚴","🤑","👽","🤖","🎃","👺","👁","🐶","🐼","🐌","👥"];
var city0 = "高谭市";
var isp0 = "Cross-GFW.org";

function getRandomInt(max){ return Math.floor(Math.random()*Math.floor(max)); }

function City_ValidCheck(para){
    return para || city0;
}

function ISP_ValidCheck(para){
    return para || isp0;
}

function Area_check(para){
    if (para=="中华民国") return "台湾";
    return para;
}

// flags 映射（略，保留你原来的）

var flags = new Map([
    ["AC","🇦🇨"],["AE","🇦🇪"],["AF","🇦🇫"],["AL","🇦🇱"],["CN","🇨🇳"],["JP","🇯🇵"],["HK","🇭🇰"],["US","🇺🇸"],["TW","🇨🇳"]
    // ... 其他省略
]);

var body = $response.body;
var obj = JSON.parse(body);

// 兼容 country code
var countryCode = obj["countryCode"] || obj["country_code"] || "";
var countryName = Area_check(obj["country"] || "");

// 兼容城市
var city = City_ValidCheck(obj["city"] || "");

// 兼容地区
var region = City_ValidCheck(obj["regionName"] || obj["region"] || "");

// 兼容 ISP / org
var isp = ISP_ValidCheck(obj["isp"] || obj["org"] || "");

// IP
var ip = obj["query"] || obj["ip"] || "";

// title / subtitle / description
var title = (flags.get(countryCode) || "🏳️") + " " + countryName + " " + city;
var subtitle = isp;
var description = "服务商: " + isp + "\n地区: " + region + "\nIP: " + ip + "\n时区: " + (obj["timezone"] || "");

// 输出
$done({ title, subtitle, ip, description });