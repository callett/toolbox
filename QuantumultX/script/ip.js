if ($response.statusCode != 200) {
    $done(null);
}

const emojis = ["🆘", "🈲", "⚠️", "🔞", "📵", "🚦", "🏖", "🖥", "📺", "🐧", "🐬", "🦉", "🍄", "⛳️", "🚴", "🤑", "👽", "🤖", "🎃", "👺", "👁", "🐶", "🐼", "🐌", "👥"];
var city0 = "高谭市";
var isp0 = "Cross-GFW.org";

function getRandomInt(max) { return Math.floor(Math.random() * Math.floor(max)); }

function City_ValidCheck(para) {
    return para || city0;
}

function ISP_ValidCheck(para) {
    return para || isp0;
}

function Area_check(para) {
    if (para == "中华民国") return "台湾";
    return para;
}

// flags 映射
var flags = new Map([
    ["AC", "🇦🇨"],
    ["AE", "🇦🇪"],
    ["AF", "🇦🇫"],
    ["AI", "🇦🇮"],
    ["AL", "🇦🇱"],
    ["AQ", "🇦🇶"],
    ["AR", "🇦🇷"],
    ["AS", "🇦🇸"],
    ["AT", "🇦🇹"],
    ["AU", "🇦🇺"],
    ["AW", "🇦🇼"],
    ["AX", "🇦🇽"],
    ["AZ", "🇦🇿"],
    ["BA", "🇧🇦"],
    ["BB", "🇧🇧"],
    ["BD", "🇧🇩"],
    ["BE", "🇧🇪"],
    ["BF", "🇧🇫"],
    ["BG", "🇧🇬"],
    ["BH", "🇧🇭"],
    ["BI", "🇧🇮"],
    ["BJ", "🇧🇯"],
    ["BM", "🇧🇲"],
    ["BN", "🇧🇳"],
    ["BO", "🇧🇴"],
    ["BR", "🇧🇷"],
    ["BS", "🇧🇸"],
    ["BT", "🇧🇹"],
    ["BV", "🇧🇻"],
    ["BW", "🇧🇼"],
    ["BY", "🇧🇾"],
    ["BZ", "🇧🇿"],
    ["CA", "🇨🇦"],
    ["CF", "🇨🇫"],
    ["CH", "🇨🇭"],
    ["CK", "🇨🇰"],
    ["CL", "🇨🇱"],
    ["CM", "🇨🇲"],
    ["CN", "🇨🇳"],
    ["CO", "🇨🇴"],
    ["CP", "🇨🇵"],
    ["CR", "🇨🇷"],
    ["CU", "🇨🇺"],
    ["CV", "🇨🇻"],
    ["CW", "🇨🇼"],
    ["CX", "🇨🇽"],
    ["CY", "🇨🇾"],
    ["CZ", "🇨🇿"],
    ["DE", "🇩🇪"],
    ["DG", "🇩🇬"],
    ["DJ", "🇩🇯"],
    ["DK", "🇩🇰"],
    ["DM", "🇩🇲"],
    ["DO", "🇩🇴"],
    ["DZ", "🇩🇿"],
    ["EA", "🇪🇦"],
    ["EC", "🇪🇨"],
    ["EE", "🇪🇪"],
    ["EG", "🇪🇬"],
    ["EH", "🇪🇭"],
    ["ER", "🇪🇷"],
    ["ES", "🇪🇸"],
    ["ET", "🇪🇹"],
    ["EU", "🇪🇺"],
    ["FI", "🇫🇮"],
    ["FJ", "🇫🇯"],
    ["FK", "🇫🇰"],
    ["FM", "🇫🇲"],
    ["FO", "🇫🇴"],
    ["FR", "🇫🇷"],
    ["GA", "🇬🇦"],
    ["GB", "🇬🇧"],
    ["HK", "🇭🇰"],
    ["HU", "🇭🇺"],
    ["ID", "🇮🇩"],
    ["IE", "🇮🇪"],
    ["IL", "🇮🇱"],
    ["IM", "🇮🇲"],
    ["IN", "🇮🇳"],
    ["IS", "🇮🇸"],
    ["IT", "🇮🇹"],
    ["JP", "🇯🇵"],
    ["KR", "🇰🇷"],
    ["LU", "🇱🇺"],
    ["MO", "🇲🇴"],
    ["MX", "🇲🇽"],
    ["MY", "🇲🇾"],
    ["NL", "🇳🇱"],
    ["PH", "🇵🇭"],
    ["RO", "🇷🇴"],
    ["RS", "🇷🇸"],
    ["RU", "🇷🇺"],
    ["RW", "🇷🇼"],
    ["SA", "🇸🇦"],
    ["SB", "🇸🇧"],
    ["SC", "🇸🇨"],
    ["SD", "🇸🇩"],
    ["SE", "🇸🇪"],
    ["SG", "🇸🇬"],
    ["TH", "🇹🇭"],
    ["TN", "🇹🇳"],
    ["TO", "🇹🇴"],
    ["TR", "🇹🇷"],
    ["TV", "🇹🇻"],
    ["TW", "🇨🇳"],
    ["UK", "🇬🇧"],
    ["UM", "🇺🇲"],
    ["US", "🇺🇸"],
    ["UY", "🇺🇾"],
    ["UZ", "🇺🇿"],
    ["VA", "🇻🇦"],
    ["VE", "🇻🇪"],
    ["VG", "🇻🇬"],
    ["VI", "🇻🇮"],
    ["VN", "🇻🇳"],
    ["ZA", "🇿🇦"],
    ["UA", "🇺🇦"],
    ["MD", "🇲🇩"],
    ["AD", "🇦🇩"],
    ["AM", "🇦🇲"],
    ["AO", "🇦🇴"],
    ["KP", "🇰🇵"],
    ["KY", "🇰🇾"],
    ["KZ", "🇰🇿"],
    ["🇱🇦", "LA"],
    ["NZ", "🇳🇿"],
    ["PK", "🇵🇰"],
    ["NO", "🇳🇴"],
    ["PT", "🇵🇹"],
    ["PL", "🇵🇱"],
    ["GR", "🇬🇷"],
    ["NG", "🇳🇬"],
    ["MV", "🇲🇻"],
    ["KH", "🇰🇭"],
    ["LA", "🇱🇦"],
    ["GU", "🇬🇺"],
    ["MN", "🇲🇳"],
    ["JO", "🇯🇴"],
    ["IR", "🇮🇷"],
    ["OM", "🇴🇲"],
    ["PS", "🇵🇸"],
    ["NP", "🇳🇵"],
    ["LB", "🇱🇧"],
    ["IQ", "🇮🇶"],
    ["SY", "🇸🇾"],
    ["QA", "🇶🇦"],
    ["GE", "🇬🇪"],
    ["LK", "🇱🇰"],
    ["KG", "🇰🇬"],
    ["ME", "🇲🇪"],
    ["LT", "🇱🇹"],
    ["MT", "🇲🇹"],
    ["MC", "🇲🇨"],
    ["HR", "🇭🇷"],
    ["MK", "🇲🇰"],
    ["LV", "🇱🇻"],
    ["SK", "🇸🇰"],
    ["GI", "🇬🇮"],
    ["SM", "🇸🇲"],
    ["LI", "🇱🇮"],
    ["RE", "🇷🇪"],
    ["PA", "🇵🇦"],
    ["GL", "🇬🇱"],
    ["PE", "🇵🇪"],
    ["PY", "🇵🇾"],
    ["JM", "🇯🇲"],
    ["SR", "🇸🇷"],
    ["GT", "🇬🇹"],
    ["PR", "🇵🇷"],
    ["HN", "🇭🇳"],
    ["NI", "🇳🇮"],
    ["GH", "🇬🇭"],
    ["MA", "🇲🇦"],
    ["LY", "🇱🇾"],
    ["KE", "🇰🇪"],
    ["MU", "🇲🇺"],
    ["TL", "🇹🇱"],
    ["SI", "🇸🇮"],
    ["GF", "🇬🇫"],
    ["TG", "🇹🇬"],
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

// === IP 段覆盖逻辑 ===
if (ip.startsWith("172.81.")) {
    countryCode = "JP";
    countryName = "日本";
    city = "东京";
}

// title / subtitle / description
var locationStr = countryName === city ? countryName : countryName + " " + city;
var title = (flags.get(countryCode) || "🏳️") + " " + locationStr;
var subtitle = isp;
var description = "服务商: " + isp + "\n地区: " + region + "\nIP: " + ip + "\n时区: " + (obj["timezone"] || "");

// 输出
$done({ title, subtitle, ip, description });