import 'package:flutter/material.dart';

/// 单个传统色数据模型
class ChineseColor {
  final String name;
  final int r;
  final int g;
  final int b;
  final String family;
  final String? description;

  const ChineseColor({
    required this.name,
    required this.r,
    required this.g,
    required this.b,
    required this.family,
    this.description,
  });

  Color toColor() => Color.fromARGB(255, r, g, b);

  /// 获取颜色描述：优先使用预设描述，否则根据色值自动生成
  String get colorDescription {
    if (description != null) return description!;
    return _generateDescription();
  }

  String _generateDescription() {
    final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
    final h = hsl.hue;
    final s = hsl.saturation;
    final l = hsl.lightness;

    if (s < 0.08) {
      if (l < 0.2) return '如墨染宣纸，沉静而深邃';
      if (l < 0.4) return '似远山含黛，朦胧而雅致';
      if (l < 0.6) return '如烟笼寒水，清淡而悠远';
      if (l < 0.8) return '似月照薄纱，素净而温柔';
      return '如初雪覆枝，纯净而明亮';
    }
    if (h < 15 || h >= 345) {
      if (l < 0.4) return '深沉如古寺朱门，历经岁月沉淀';
      if (l < 0.65) return '灿若丹霞映晚照，温暖而热烈';
      return '柔如桃花初绽，春风拂面之色';
    } else if (h < 35) {
      if (l < 0.4) return '沉稳如秋日赭石，大地之色';
      if (l < 0.65) return '暖若夕阳橘光，温润而明朗';
      return '淡如晨曦初露，柔和而温馨';
    } else if (h < 55) {
      if (l < 0.4) return '古朴如陈年檀木，沉稳而厚重';
      if (l < 0.65) return '明如秋菊傲霜，高洁而灿烂';
      return '轻若鹅黄新柳，春意盎然之色';
    } else if (h < 75) {
      if (l < 0.4) return '深如暮秋苍穗，丰收之色';
      if (l < 0.65) return '灿若金缕衣裳，华贵而明亮';
      return '淡如稻花飘香，清新而雅致';
    } else if (h < 105) {
      if (l < 0.4) return '浓如深林蓊郁，生机勃勃';
      if (l < 0.65) return '翠若春柳拂堤，清新而灵动';
      return '嫩如新芽初萌，充满希望之色';
    } else if (h < 150) {
      if (l < 0.4) return '深如松柏常青，坚韧而沉稳';
      if (l < 0.65) return '碧若山间翠竹，清雅而高洁';
      return '淡如薄荷清风，沁人心脾之色';
    } else if (h < 195) {
      if (l < 0.4) return '幽如深潭碧水，神秘而宁静';
      if (l < 0.65) return '清若雨后青瓷，温润而典雅';
      return '澈如山泉映月，清透而灵秀';
    } else if (h < 240) {
      if (l < 0.4) return '深如夜空藏蓝，深邃而辽远';
      if (l < 0.65) return '澄若秋水长天，开阔而明净';
      return '淡如晴空万里，悠远而宁静';
    } else if (h < 285) {
      if (l < 0.4) return '幽如紫府仙宫，神秘而高贵';
      if (l < 0.65) return '雅若堇花含露，淡雅而脱俗';
      return '柔如薰衣草田，浪漫而温柔';
    } else {
      if (l < 0.4) return '浓如酱紫檀香，沉稳而华贵';
      if (l < 0.65) return '艳若蔷薇盛放，热烈而优雅';
      return '柔如瑶池仙露，梦幻而轻盈';
    }
  }

  Color get textColor {
    final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
    if (hsl.lightness > 0.55) {
      return hsl
          .withLightness((hsl.lightness - 0.35).clamp(0.08, 0.35))
          .withSaturation((hsl.saturation * 1.2).clamp(0.0, 1.0))
          .toColor();
    } else {
      return hsl
          .withLightness((hsl.lightness + 0.35).clamp(0.65, 0.92))
          .withSaturation((hsl.saturation * 0.8).clamp(0.0, 1.0))
          .toColor();
    }
  }
}

class ColorFamily {
  final String id;
  final String name;
  final List<ChineseColor> colors;
  const ColorFamily({required this.id, required this.name, required this.colors});
}

class TraditionalChineseColors {
  static const List<ColorFamily> families = [
    // ==================== 红色系 ====================
    ColorFamily(id: 'red', name: '红色系', colors: [
      ChineseColor(name: '杨妃', r: 240, g: 145, b: 160, family: 'red', description: '取自杨贵妃醉酒后双颊微红之色，白居易《长恨歌》中倾城之色'),
      ChineseColor(name: '木兰', r: 102, g: 64, b: 31, family: 'red', description: '花木兰替父从军，此色如木兰树皮般沉稳刚毅，暗含巾帼之志'),
      ChineseColor(name: '胭脂水', r: 185, g: 90, b: 137, family: 'red', description: '古代女子以红蓝花汁制胭脂，溶于水中呈此色，闺阁梳妆之色'),
      ChineseColor(name: '盈盈', r: 249, g: 211, b: 227, family: 'red', description: '语出《古诗十九首》"盈盈一水间"，如隔水相望少女面颊之色'),
      ChineseColor(name: '彤管', r: 226, g: 162, b: 172, family: 'red', description: '《诗经·邶风》"贻我彤管"，古代红色笔管，恋人间的定情之物'),
      ChineseColor(name: '紫茎屏风', r: 167, g: 98, b: 131, family: 'red', description: '唐代宫廷屏风以紫茎花卉为饰，如屏风上绽放的紫红花枝'),
      ChineseColor(name: '银红', r: 231, g: 202, b: 211, family: 'red', description: '明清织锦经典色，银丝与红丝交织，如月光洒在红绸上的柔光'),
      ChineseColor(name: '咸池', r: 216, g: 169, b: 169, family: 'red', description: '上古神话中太阳沐浴之处，日出时天边泛起的温暖红晕'),
      ChineseColor(name: '红踯躅', r: 184, g: 53, b: 112, family: 'red', description: '踯躅即杜鹃花，相传杜鹃啼血染红山花，是蜀地最凄美的传说'),
      ChineseColor(name: '粉米', r: 239, g: 196, b: 206, family: 'red', description: '古代以粉米为祭祀供品，此色淡雅如研磨后的粉米，温和的敬意'),
      ChineseColor(name: '莲红', r: 217, g: 160, b: 179, family: 'red', description: '周敦颐《爱莲说》"出淤泥而不染"的莲花之色，清雅高洁'),
      ChineseColor(name: '胭脂紫', r: 176, g: 67, b: 111, family: 'red', description: '胭脂浓重处呈紫，汉代宫女以此色点唇，后宫最浓烈的妆容'),
      ChineseColor(name: '桃夭', r: 246, g: 190, b: 200, family: 'red', description: '《诗经·周南》"桃之夭夭，灼灼其华"，春日桃花最娇嫩的粉色'),
      ChineseColor(name: '雌霓', r: 207, g: 146, b: 158, family: 'red', description: '古人称虹为雄、霓为雌，雌霓色淡而柔美，雨后最温婉的彩虹'),
      ChineseColor(name: '魏红', r: 167, g: 55, b: 102, family: 'red', description: '北魏崇尚之红，洛阳牡丹名品，欧阳修赞"天下真花独牡丹"'),
      ChineseColor(name: '水红', r: 217, g: 176, b: 193, family: 'red', description: '如红色倒映水中般清透，《红楼梦》中常见衣裳配色，闺秀之色'),
      ChineseColor(name: '缣缘', r: 206, g: 136, b: 146, family: 'red', description: '缣为细密丝织品，缘为边饰，如丝帛镶边的淡红，织造之精致'),
      ChineseColor(name: '紫府', r: 153, g: 93, b: 127, family: 'red', description: '道教神仙居所，紫气东来之地，李商隐诗"紫府仙人号宝灯"'),
      ChineseColor(name: '夕岚', r: 227, g: 173, b: 185, family: 'red', description: '傍晚山间雾气被夕阳染红之色，王维笔下山水暮色的温柔'),
      ChineseColor(name: '长春', r: 220, g: 107, b: 130, family: 'red', description: '月季花古称，因四季常开而名长春，宋代皇家园林珍贵花卉之色'),
      ChineseColor(name: '魏紫', r: 144, g: 55, b: 84, family: 'red', description: '洛阳牡丹四大名品之一，宋代魏仁溥家培育，与姚黄并称花中二绝'),
      ChineseColor(name: '绛纱', r: 178, g: 119, b: 119, family: 'red', description: '唐代宰相议事所用绛纱帷幕之色，"绛纱笼烛影"是权力的象征'),
      ChineseColor(name: '渥赭', r: 221, g: 107, b: 123, family: 'red', description: '渥为浓厚，赭为红土，如雨后红土地般浓郁，大地最质朴的颜色'),
      ChineseColor(name: '地血', r: 129, g: 67, b: 98, family: 'red', description: '古代矿物颜料，取自含铁红土，如大地血脉般深沉，最古老的颜料'),
      ChineseColor(name: '茹蕙', r: 163, g: 95, b: 101, family: 'red', description: '蕙草为兰之一种，屈原《离骚》"纫秋兰以为佩"，温润内敛之色'),
      ChineseColor(name: '红麴', r: 205, g: 115, b: 114, family: 'red', description: '红曲米发酵而成的天然色素，宋代起用于食品染色，饮食文化的印记'),
      ChineseColor(name: '芥拾紫', r: 96, g: 38, b: 65, family: 'red', description: '芥子虽小蕴含大千世界，深沉如佛家"芥子纳须弥"的禅意'),
      ChineseColor(name: '美人祭', r: 195, g: 92, b: 106, family: 'red', description: '相传为祭祀西施所用之色，吴越春秋美人计的悲壮化作这抹凄艳'),
      ChineseColor(name: '紫梅', r: 187, g: 122, b: 144, family: 'red', description: '寒梅傲雪时花瓣泛紫之色，陆游"只有香如故"的风骨'),
      ChineseColor(name: '紫薄汗', r: 187, g: 161, b: 203, family: 'red', description: '唐代名马毛色，汗血宝马奔驰时皮毛泛出的紫红光泽'),
      ChineseColor(name: '唇脂', r: 194, g: 81, b: 96, family: 'red', description: '古代口脂以朱砂蜂蜡调制，女子妆奁中最珍贵的一抹"点绛唇"'),
      ChineseColor(name: '紫矿', r: 158, g: 78, b: 86, family: 'red', description: '紫铆虫分泌的天然树脂染料，丝绸之路上从印度传入的珍贵贸易品'),
      ChineseColor(name: '退红', r: 240, g: 207, b: 227, family: 'red', description: '红色经日晒褪去后的柔和之色，如旧时光中渐渐泛白的红窗帘'),
      ChineseColor(name: '鞓红', r: 176, g: 69, b: 82, family: 'red', description: '鞓为皮革腰带，唐代官员以红色皮带为饰，庄重而不失华丽'),
      ChineseColor(name: '紫诰', r: 118, g: 65, b: 85, family: 'red', description: '古代帝王诏书用紫色绫锦包裹，"紫诰"即圣旨，至高权威的象征'),
      ChineseColor(name: '昌容', r: 220, g: 199, b: 225, family: 'red', description: '传说中的仙女，服食云母而容颜不老，如仙人肌肤般莹润通透'),
      ChineseColor(name: '葡萄褐', r: 158, g: 105, b: 109, family: 'red', description: '张骞出使西域带回葡萄，如成熟葡萄皮般深沉，丝路文化的印记'),
      ChineseColor(name: '苕荣', r: 238, g: 109, b: 61, family: 'red', description: '苕为凌霄花，《诗经》"苕之华"，凌霄花盛放时的橙红之色'),
      ChineseColor(name: '樱花', r: 228, g: 184, b: 213, family: 'red', description: '樱花原产中国喜马拉雅山区，唐代已有赏樱之风，白居易诗中之色'),
      ChineseColor(name: '蚩尤旗', r: 168, g: 88, b: 88, family: 'red', description: '古代星象名，蚩尤旗星出现时天边泛红，上古战神的颜色'),
      ChineseColor(name: '扶光', r: 240, g: 194, b: 162, family: 'red', description: '扶桑之光，神话中太阳从扶桑树升起时的第一缕光芒'),
      ChineseColor(name: '丁香', r: 206, g: 147, b: 191, family: 'red', description: '戴望舒《雨巷》"丁香一样的姑娘"，丁香花开时淡紫带粉的忧郁'),
      ChineseColor(name: '苏方', r: 129, g: 71, b: 76, family: 'red', description: '苏方木为古代重要红色染料，经丝绸之路传入，染出的红沉稳持久'),
      ChineseColor(name: '十样锦', r: 248, g: 198, b: 181, family: 'red', description: '唐代蜀锦名品，十种颜色织成华美图案，薛涛以此笺纸名动天下'),
      ChineseColor(name: '木槿', r: 186, g: 121, b: 177, family: 'red', description: '木槿花朝开暮落，《诗经》"颜如舜华"，舜华即木槿，喻美人易逝'),
      ChineseColor(name: '霁红', r: 124, g: 68, b: 73, family: 'red', description: '景德镇名瓷釉色，雨过天晴后窑变而成，"千窑一宝"之珍'),
      ChineseColor(name: '海天霞', r: 200, g: 166, b: 148, family: 'red', description: '海天相接处朝霞映照之色，王勃"落霞与孤鹜齐飞"的壮美'),
      ChineseColor(name: '茈藐', r: 166, g: 126, b: 183, family: 'red', description: '茈草即紫草，《神农本草经》记载的染料药材，古人染紫之源'),
      ChineseColor(name: '蜜褐', r: 104, g: 54, b: 50, family: 'red', description: '如陈年蜂蜜凝结后的深褐，甜蜜中带着岁月的醇厚'),
      ChineseColor(name: '骍刚', r: 245, g: 176, b: 135, family: 'red', description: '骍为赤色牛马，《礼记》祭祀用赤色牲畜，是古代礼制中的神圣之色'),
      ChineseColor(name: '膠紫', r: 204, g: 115, b: 160, family: 'red', description: '以动物胶调和紫色颜料而成，是古代书画家调色盘上不可或缺的一色'),
      ChineseColor(name: '福色', r: 102, g: 43, b: 47, family: 'red', description: '民间以深红为福，春联窗花皆用此色，是千家万户辞旧迎新的喜庆'),
      ChineseColor(name: '朱颜酡', r: 242, g: 154, b: 118, family: 'red', description: '酡为饮酒后面红之色，李白"举杯邀明月"后的微醺，豪放不羁'),
      ChineseColor(name: '龙膏烛', r: 222, g: 130, b: 167, family: 'red', description: '传说龙脂所制之烛，燃烧时发出此色光芒，是帝王宫殿中的奇珍'),
      ChineseColor(name: '油紫', r: 66, g: 11, b: 47, family: 'red', description: '如紫漆般深沉油亮，明代家具常用此色漆面，沉稳中透着华贵'),
      ChineseColor(name: '赪霞', r: 241, g: 143, b: 96, family: 'red', description: '赪为深红，朝霞满天时的浓烈之色，"朝霞不出门"的古老智慧'),
      ChineseColor(name: '苏梅', r: 221, g: 118, b: 148, family: 'red', description: '苏州梅花盛开时的粉红，江南园林中最动人的早春风景'),
      ChineseColor(name: '丹雘', r: 230, g: 60, b: 18, family: 'red', description: '丹雘为朱红色矿物颜料，古代宫殿梁柱必用此色，是皇权建筑的标志'),
      ChineseColor(name: '赪尾', r: 239, g: 132, b: 93, family: 'red', description: '赪尾鱼尾鳍赤红如火，《山海经》中的神异之鱼，水中的一抹烈焰'),
      ChineseColor(name: '琅玕紫', r: 203, g: 92, b: 131, family: 'red', description: '琅玕为传说中的仙树美玉，此色如琅玕树上结出的紫色宝珠'),
      ChineseColor(name: '缙云', r: 238, g: 121, b: 89, family: 'red', description: '缙云为黄帝炼丹之地，丹炉火光映照云霞的赤橙之色'),
      ChineseColor(name: '小红', r: 185, g: 119, b: 98, family: 'red', description: '宋词中常见的女子名，"小红低唱我吹箫"，是江南烟雨中的温婉'),
      ChineseColor(name: '朱孔阳', r: 184, g: 26, b: 53, family: 'red', description: '《诗经》"我朱孔阳"，朱色鲜明之意，是周代礼服最正统的红'),
      ChineseColor(name: '琼琚', r: 215, g: 127, b: 102, family: 'red', description: '《诗经·卫风》"投我以木瓜，报之以琼琚"，美玉般温润的赠礼之色'),
      ChineseColor(name: '岱赭', r: 221, g: 107, b: 79, family: 'red', description: '泰山赭石之色，五岳之首的大地本色，厚重而庄严'),
      ChineseColor(name: '丹艧', r: 200, g: 22, b: 29, family: 'red', description: '艧为彩绘船只，古代龙舟以丹色涂饰，是端午竞渡的热烈'),
      ChineseColor(name: '朱柿', r: 237, g: 109, b: 70, family: 'red', description: '深秋柿子成熟时的朱红，"柿叶翻红霜景秋"，丰收的喜悦之色'),
      ChineseColor(name: '艴炽', r: 203, g: 82, b: 62, family: 'red', description: '艴为面红耳赤，炽为火热，如烈火燃烧般炽热的赤红'),
      ChineseColor(name: '水华朱', r: 167, g: 33, b: 38, family: 'red', description: '水中朱砂精华所成，古代炼丹术中最珍贵的丹砂之色'),
      ChineseColor(name: '鹤顶红', r: 210, g: 71, b: 53, family: 'red', description: '丹顶鹤头顶的赤红，古人视为吉祥长寿之色，也是传说中的剧毒之名'),
      ChineseColor(name: '赤缇', r: 186, g: 91, b: 73, family: 'red', description: '缇为橘红色丝织品，汉代官府文书用缇帙包裹，是公文的庄重之色'),
      ChineseColor(name: '胭脂虫', r: 171, g: 29, b: 34, family: 'red', description: '胭脂虫为珍贵的天然红色染料来源，一磅染料需七万只虫体'),
      ChineseColor(name: '纁黄', r: 186, g: 81, b: 64, family: 'red', description: '纁为浅红色，《周礼》中祭祀天地的礼服之色，介于红黄之间'),
      ChineseColor(name: '棠梨', r: 177, g: 90, b: 67, family: 'red', description: '棠梨即杜梨，白居易"玉容寂寞泪阑干，梨花一枝春带雨"的秋实之色'),
      ChineseColor(name: '朱樱', r: 129, g: 29, b: 34, family: 'red', description: '樱桃成熟时的深朱红，白居易"含桃最说出东吴"，是初夏的甜蜜'),
      ChineseColor(name: '朱殷', r: 185, g: 58, b: 38, family: 'red', description: '殷红如血，《左传》"血流漂杵"的战场之色，是历史最沉重的红'),
      ChineseColor(name: '石榴裙', r: 177, g: 59, b: 46, family: 'red', description: '唐代女子最爱的裙色，"拜倒在石榴裙下"的典故由此而来'),
      ChineseColor(name: '大繎', r: 130, g: 35, b: 39, family: 'red', description: '繎为深红色丝线，古代织锦中最浓烈的经线之色，是织女的心血'),
      ChineseColor(name: '朱草', r: 166, g: 64, b: 54, family: 'red', description: '传说中的祥瑞之草，茎叶皆红，帝王圣德则朱草生，是太平盛世的征兆'),
      ChineseColor(name: '赤灵', r: 149, g: 64, b: 36, family: 'red', description: '赤帝之灵，五行属火，南方之色，是华夏文明中火德的象征'),
      ChineseColor(name: '顺圣', r: 124, g: 25, b: 30, family: 'red', description: '顺天应圣之色，古代帝王登基大典所用的庄严深红'),
      ChineseColor(name: '佛赤', r: 143, g: 61, b: 44, family: 'red', description: '佛像金身底色常用此赤，敦煌壁画中菩萨袈裟的庄严之色'),
      ChineseColor(name: '缋茂', r: 158, g: 42, b: 34, family: 'red', description: '缋为彩绘，茂为繁盛，如古代彩绘建筑上最浓烈的朱红装饰'),
      ChineseColor(name: '爵头', r: 99, g: 18, b: 22, family: 'red', description: '爵为古代青铜酒器，此色如爵中陈年美酒般深沉醇厚'),
      ChineseColor(name: '朱湛', r: 149, g: 48, b: 46, family: 'red', description: '湛为深沉，朱湛即深沉的朱红，如古寺大殿柱上历经百年的漆色'),
      ChineseColor(name: '丹秫', r: 135, g: 52, b: 36, family: 'red', description: '秫为高粱，红高粱成熟时的深红，莫言笔下那片热烈的高粱地'),
      ChineseColor(name: '麒麟竭', r: 76, g: 30, b: 26, family: 'red', description: '龙血树脂制成的珍贵药材与颜料，古称"麒麟竭"，是最名贵的红色'),
      ChineseColor(name: '银朱', r: 209, g: 64, b: 32, family: 'red', description: '以水银与硫磺炼制的朱红颜料，比天然朱砂更鲜艳，是炼丹术的产物'),
      ChineseColor(name: '黄丹', r: 204, g: 85, b: 20, family: 'red', description: '铅丹氧化而成的橙红色颜料，古代道士炼丹的副产品，也用于中药'),
      ChineseColor(name: '珊瑚赫', r: 193, g: 44, b: 31, family: 'red', description: '深海珊瑚的赫红之色，古代视红珊瑚为至宝，"珊瑚在网"喻珍才'),
      ChineseColor(name: '洛神珠', r: 210, g: 57, b: 24, family: 'red', description: '曹植《洛神赋》中洛水女神佩戴的明珠之色，"翩若惊鸿"的绝世风华'),
      ChineseColor(name: '槨丹', r: 233, g: 72, b: 64, family: 'red', description: '槨为外棺，古代帝王以丹漆涂棺，是对逝者最高规格的礼遇'),
    ]),
    // ==================== 黄色系 ====================
    ColorFamily(id: 'yellow', name: '黄色系', colors: [
      ChineseColor(name: '半见', r: 255, g: 251, b: 199, family: 'yellow', description: '如月光半隐云后，若隐若现的淡黄，是李清照"月满西楼"的朦胧'),
      ChineseColor(name: '翠樽', r: 205, g: 209, b: 113, family: 'yellow', description: '翠色酒樽中盛满的琼浆之色，李白"金樽清酒斗十千"的豪迈'),
      ChineseColor(name: '老茯神', r: 170, g: 133, b: 52, family: 'yellow', description: '茯神为松根上生长的药材，陈年茯神色泽深沉，是中医药文化的沉淀'),
      ChineseColor(name: '断肠', r: 236, g: 235, b: 194, family: 'yellow', description: '断肠草花色淡黄，虽名凄婉却是古代重要药材，美丽与危险并存'),
      ChineseColor(name: '田赤', r: 225, g: 221, b: 132, family: 'yellow', description: '田黄石中的赤色品种，寿山石之王，"一两田黄三两金"的珍贵'),
      ChineseColor(name: '流黄', r: 139, g: 112, b: 66, family: 'yellow', description: '《古诗十九首》"纤纤擢素手，札札弄机杼"，织女所织的黄色丝绢'),
      ChineseColor(name: '葱青', r: 237, g: 241, b: 187, family: 'yellow', description: '春葱初生时的嫩黄带绿，是菜园里最清新的颜色，烟火人间的生机'),
      ChineseColor(name: '禹余粮', r: 225, g: 210, b: 121, family: 'yellow', description: '传说大禹治水时留下的余粮化为此石，是一味安神止血的中药'),
      ChineseColor(name: '青白玉', r: 202, g: 197, b: 160, family: 'yellow', description: '和田玉中青白相间的品种，温润如君子之德，"君子比德于玉"'),
      ChineseColor(name: '女贞黄', r: 247, g: 238, b: 173, family: 'yellow', description: '女贞树果实成熟时的淡黄，此树冬不落叶，古人以之喻贞节'),
      ChineseColor(name: '姚黄', r: 214, g: 188, b: 70, family: 'yellow', description: '洛阳牡丹四大名品之首，姚氏家培育的黄牡丹，被誉为"花王"'),
      ChineseColor(name: '玉色', r: 235, g: 228, b: 209, family: 'yellow', description: '美玉的天然色泽，《礼记》"君子无故玉不去身"，温润而泽'),
      ChineseColor(name: '莺儿', r: 235, g: 225, b: 169, family: 'yellow', description: '黄莺羽毛的嫩黄，杜甫"两个黄鹂鸣翠柳"中最明快的春色'),
      ChineseColor(name: '太一余粮', r: 213, g: 180, b: 89, family: 'yellow', description: '道教至高神太一所遗之粮，化为黄色矿石，是修仙炼丹的辅料'),
      ChineseColor(name: '骨缥', r: 235, g: 227, b: 199, family: 'yellow', description: '缥为淡青色丝帛，骨缥指其底色，如古籍书页泛黄的温暖色调'),
      ChineseColor(name: '桑蕾', r: 234, g: 216, b: 154, family: 'yellow', description: '桑树春日发芽时的嫩黄，蚕桑文化是华夏文明的根基之一'),
      ChineseColor(name: '栾华', r: 192, g: 173, b: 94, family: 'yellow', description: '栾树秋日开花，满树金黄如华盖，古代常植于学宫，又名"灯笼树"'),
      ChineseColor(name: '黄润', r: 223, g: 214, b: 184, family: 'yellow', description: '如美玉般黄而润泽，苏轼"温润而泽，仁也"，是君子品格的颜色'),
      ChineseColor(name: '绢纨', r: 236, g: 224, b: 147, family: 'yellow', description: '绢纨为精细丝织品，班婕妤《怨歌行》"裁为合欢扇"的素雅之色'),
      ChineseColor(name: '秋香', r: 191, g: 156, b: 70, family: 'yellow', description: '秋日桂花飘香时的金黄，"桂子月中落，天香云外飘"的芬芳之色'),
      ChineseColor(name: '缣缃', r: 213, g: 200, b: 160, family: 'yellow', description: '缣缃为淡黄色丝帛，古代用以包裹书卷，"缃帙"即书卷的代称'),
      ChineseColor(name: '少艾', r: 227, g: 235, b: 152, family: 'yellow', description: '《孟子》"知好色则慕少艾"，少艾指年轻美好，如初春嫩芽的鲜活'),
      ChineseColor(name: '大赤', r: 170, g: 150, b: 73, family: 'yellow', description: '古代五色之一的正黄，天子专用之色，"黄袍加身"的帝王气象'),
      ChineseColor(name: '佩玖', r: 172, g: 159, b: 138, family: 'yellow', description: '《诗经》"投我以木李，报之以琼玖"，玖为黑色美玉，此为其温润底色'),
      ChineseColor(name: '绮钱', r: 216, g: 222, b: 138, family: 'yellow', description: '绮为有花纹的丝织品，钱为圆形，如铜钱般圆润的黄绿丝绸之色'),
      ChineseColor(name: '苍黄', r: 182, g: 160, b: 20, family: 'yellow', description: '《易经》"天玄地黄"，苍黄为天地变色之际，是沧桑巨变的颜色'),
      ChineseColor(name: '大块', r: 191, g: 167, b: 130, family: 'yellow', description: '庄子"大块噫气，其名为风"，大块即大地，此色如广袤原野的土黄'),
      ChineseColor(name: '蜜合', r: 223, g: 215, b: 194, family: 'yellow', description: '蜂蜜与花粉调和之色，是养蜂人家最甜蜜的收获，温暖而醇厚'),
      ChineseColor(name: '沙饧', r: 191, g: 166, b: 112, family: 'yellow', description: '饧为麦芽糖，沙饧即砂糖色，是古代糖坊里最甜蜜的颜色'),
      ChineseColor(name: '地籁', r: 223, g: 206, b: 180, family: 'yellow', description: '庄子"地籁则众窍是已"，大地之声，此色如黄土高原的温厚'),
      ChineseColor(name: '仙米', r: 212, g: 201, b: 170, family: 'yellow', description: '传说中仙人食用的米粒之色，道教辟谷文化中的神圣食粮'),
      ChineseColor(name: '黄螺', r: 180, g: 163, b: 121, family: 'yellow', description: '螺钿工艺中黄色贝壳的光泽，唐代螺钿镜背上最温润的镶嵌'),
      ChineseColor(name: '假山南', r: 212, g: 193, b: 166, family: 'yellow', description: '园林假山南面受阳光照射的暖黄色调，是苏州园林的光影之美'),
      ChineseColor(name: '高粱', r: 196, g: 183, b: 152, family: 'yellow', description: '高粱穗成熟时的淡黄，是北方大地上最朴实的丰收之色'),
      ChineseColor(name: '蒸栗', r: 143, g: 138, b: 95, family: 'yellow', description: '蒸熟的板栗之色，《礼记》中秋日祭祀的供品，是团圆的味道'),
      ChineseColor(name: '巨吕', r: 170, g: 142, b: 89, family: 'yellow', description: '古代十二律吕之一，黄钟大吕的庄严之色，是礼乐文明的基调'),
      ChineseColor(name: '石蜜', r: 212, g: 191, b: 137, family: 'yellow', description: '石蜜即冰糖，唐代从西域传入的珍贵甜品，如琥珀般晶莹的黄'),
      ChineseColor(name: '大云', r: 148, g: 120, b: 79, family: 'yellow', description: '大云即肉苁蓉，沙漠中的珍贵药材，"沙漠人参"的深沉土黄'),
      ChineseColor(name: '降真香', r: 158, g: 131, b: 88, family: 'yellow', description: '道教焚香祈福所用的珍贵香料，燃烧时烟色如此，可"降诸真仙"'),
      ChineseColor(name: '紫花布', r: 190, g: 167, b: 139, family: 'yellow', description: '明清民间常用的棉布染色，紫花布是百姓日常衣着的朴素之色'),
      ChineseColor(name: '吉金', r: 137, g: 109, b: 71, family: 'yellow', description: '吉金即青铜器的美称，商周青铜器历经千年氧化后的古朴金色'),
      ChineseColor(name: '黄封', r: 202, g: 178, b: 114, family: 'yellow', description: '宋代御酒以黄纸封口，"黄封"成为御赐美酒的代称'),
      ChineseColor(name: '养生主', r: 181, g: 155, b: 127, family: 'yellow', description: '庄子《养生主》篇，"吾生也有涯"，此色如养生之道般温和中正'),
      ChineseColor(name: '远志', r: 124, g: 102, b: 59, family: 'yellow', description: '远志为安神益智的中药，根皮深褐，是中医"治心"的良药之色'),
      ChineseColor(name: '射干', r: 124, g: 98, b: 68, family: 'yellow', description: '射干为鸢尾科药用植物，根茎深黄，《神农本草经》中的清热良药'),
      ChineseColor(name: '油葫芦', r: 100, g: 77, b: 49, family: 'yellow', description: '油葫芦即蟋蟀的一种，秋夜鸣虫的深褐之色，是古人斗蟋蟀的雅趣'),
      ChineseColor(name: '龙战', r: 95, g: 67, b: 33, family: 'yellow', description: '《易经》"龙战于野，其血玄黄"，天地交战时的混沌之色'),
      ChineseColor(name: '赩缔', r: 128, g: 76, b: 46, family: 'yellow', description: '赩为深红，缔为结合，红与褐交织的深沉之色，如古代漆器的底色'),
      ChineseColor(name: '葭灰', r: 190, g: 177, b: 170, family: 'yellow', description: '古代以芦苇灰测节气，冬至时灰飞管动，是二十四节气的科学智慧'),
      ChineseColor(name: '珠子褐', r: 195, g: 168, b: 157, family: 'yellow', description: '如珍珠般圆润的褐色，是宋代文人雅士茶具上最温润的釉色'),
      ChineseColor(name: '黄埃', r: 180, g: 146, b: 115, family: 'yellow', description: '白居易《长恨歌》"黄埃散漫风萧索"，安史之乱中的苍凉之色'),
      ChineseColor(name: '黄栗留', r: 254, g: 220, b: 89, family: 'yellow', description: '黄鹂鸟的古称，杜甫"两个黄鹂鸣翠柳"中那抹最明亮的金黄'),
      ChineseColor(name: '露褐', r: 189, g: 130, b: 83, family: 'yellow', description: '晨露沾染枯叶后的褐色，是深秋清晨最诗意的颜色'),
      ChineseColor(name: '弗肯红', r: 236, g: 217, b: 199, family: 'yellow', description: '似红非红、欲红还休的含蓄之色，如少女羞涩时若有若无的红晕'),
      ChineseColor(name: '嫩鹅黄', r: 222, g: 200, b: 103, family: 'yellow', description: '雏鹅绒毛的嫩黄，是春天最柔软的颜色，充满新生的喜悦'),
      ChineseColor(name: '蛾黄', r: 190, g: 138, b: 47, family: 'yellow', description: '古代女子以黄粉饰额，称为"蛾黄"，是南北朝时期流行的妆容'),
      ChineseColor(name: '赤璋', r: 179, g: 193, b: 153, family: 'yellow', description: '璋为半圭形玉器，赤璋用于祭祀南方，是古代六器之一的礼玉之色'),
      ChineseColor(name: '黄河琉璃', r: 229, g: 168, b: 75, family: 'yellow', description: '黄河水裹挟泥沙的浑金之色，"黄河之水天上来"的磅礴气势'),
      ChineseColor(name: '光明砂', r: 204, g: 93, b: 32, family: 'yellow', description: '朱砂中品质最佳者称光明砂，晶莹如镜，是道教炼丹的至宝'),
      ChineseColor(name: '如梦令', r: 221, g: 187, b: 153, family: 'yellow', description: '李清照词牌名，"常记溪亭日暮"的温暖黄昏之色'),
      ChineseColor(name: '杏子', r: 218, g: 146, b: 51, family: 'yellow', description: '杏子成熟时的金黄，"牧童遥指杏花村"，是春日乡村的温暖记忆'),
      ChineseColor(name: '柘黄', r: 198, g: 121, b: 33, family: 'yellow', description: '以柘木汁染成的黄色，唐代起为帝王专用，"黄袍"即柘黄袍'),
      ChineseColor(name: '茧色', r: 198, g: 162, b: 104, family: 'yellow', description: '蚕茧的天然淡黄，是丝绸之路起点的颜色，华夏蚕桑文明的象征'),
      ChineseColor(name: '红友', r: 217, g: 136, b: 61, family: 'yellow', description: '宋人以酒为"红友"，此色如陈年黄酒般温润，是文人雅集的知己'),
      ChineseColor(name: '媚蝶', r: 210, g: 163, b: 55, family: 'yellow', description: '蝴蝶翅膀上的金黄斑纹，庄周梦蝶的哲思化作这抹灵动之色'),
      ChineseColor(name: '芸黄', r: 210, g: 163, b: 108, family: 'yellow', description: '芸草泛黄之色，古人以芸草夹书防虫，"芸窗"即书房的雅称'),
      ChineseColor(name: '库金', r: 225, g: 138, b: 59, family: 'yellow', description: '国库中金锭的颜色，是古代财富与国力的象征'),
      ChineseColor(name: '黄流', r: 159, g: 96, b: 39, family: 'yellow', description: '《诗经》"黄流在中"，祭祀用的郁金香酒之色，庄严而神圣'),
      ChineseColor(name: '椒房', r: 219, g: 156, b: 89, family: 'yellow', description: '汉代皇后居所以花椒和泥涂壁，取温暖芳香之意，是后宫的尊贵'),
      ChineseColor(name: '鞠衣', r: 211, g: 162, b: 55, family: 'yellow', description: '《周礼》皇后六服之一，以鞠草染成的黄色礼服，蚕桑之礼的庄重'),
      ChineseColor(name: '靺鞨', r: 159, g: 82, b: 33, family: 'yellow', description: '靺鞨为东北古族名，其贡品琥珀之色，是边疆贸易的珍贵记忆'),
      ChineseColor(name: '金埒', r: 190, g: 148, b: 87, family: 'yellow', description: '金埒为以金铺地的跑马场，南朝王僧达的奢华，是贵族生活的缩影'),
      ChineseColor(name: '黄不老', r: 219, g: 155, b: 52, family: 'yellow', description: '黄精别名"黄不老"，道教视为延年益寿的仙药，服之可长生'),
      ChineseColor(name: '九斤黄', r: 221, g: 176, b: 120, family: 'yellow', description: '九斤黄为中国名鸡品种，羽毛金黄丰满，是农耕文化的活化石'),
      ChineseColor(name: '雌黄', r: 180, g: 136, b: 77, family: 'yellow', description: '雌黄矿物可涂改文字，"信口雌黄"典故由此而来，是古代的修正液'),
      ChineseColor(name: '郁金裙', r: 208, g: 134, b: 53, family: 'yellow', description: '以郁金香草染成的黄裙，唐代女子最爱的裙色之一，明艳动人'),
      ChineseColor(name: '密陀僧', r: 179, g: 147, b: 75, family: 'yellow', description: '氧化铅矿物，古代用于陶瓷釉料和中药，是丝路传来的炼金之色'),
      ChineseColor(name: '沉香', r: 153, g: 128, b: 108, family: 'yellow', description: '沉香木历经百年结香，"沉檀龙麝"四大名香之首，一片万金'),
      ChineseColor(name: '明茶褐', r: 151, g: 131, b: 104, family: 'yellow', description: '明代茶道中上品茶汤之色，陆羽《茶经》所推崇的清雅茶色'),
      ChineseColor(name: '栗壳', r: 210, g: 98, b: 57, family: 'yellow', description: '板栗外壳的红褐色，是秋日山林中最温暖的果实之色'),
      ChineseColor(name: '夏篇', r: 201, g: 175, b: 157, family: 'yellow', description: '夏日竹简的淡黄之色，古人以竹简记事，是华夏文字载体的本色'),
      ChineseColor(name: '麝香褐', r: 218, g: 158, b: 80, family: 'yellow', description: '麝香为名贵香料，此色如麝香囊的深褐，是古代香文化的珍贵记忆'),
      ChineseColor(name: '檀唇', r: 218, g: 158, b: 140, family: 'yellow', description: '以檀香木色喻女子唇色，温庭筠"小山重叠金明灭，鬓云欲度香腮雪"'),
      ChineseColor(name: '荆褐', r: 144, g: 108, b: 74, family: 'yellow', description: '荆条编织器物的褐色，"负荆请罪"中廉颇背负的荆条之色'),
      ChineseColor(name: '椒褐', r: 114, g: 69, b: 58, family: 'yellow', description: '花椒果实成熟时的深褐，是川菜文化中最热烈的调味之色'),
      ChineseColor(name: '紫磨金', r: 188, g: 131, b: 107, family: 'yellow', description: '佛经中形容佛身"紫磨金色"，是最纯净的黄金经反复锤炼之色'),
      ChineseColor(name: '驼褐', r: 124, g: 91, b: 62, family: 'yellow', description: '骆驼毛的褐色，丝绸之路上驼队穿越大漠的颜色，是远行的记忆'),
      ChineseColor(name: '枣褐', r: 104, g: 54, b: 26, family: 'yellow', description: '干枣的深褐之色，"日食三枣，容颜不老"，是养生文化的朴素智慧'),
      ChineseColor(name: '檀色', r: 178, g: 109, b: 83, family: 'yellow', description: '檀木的天然色泽，紫檀黄檀皆为名贵木材，是明式家具的灵魂之色'),
      ChineseColor(name: '温韎', r: 143, g: 79, b: 49, family: 'yellow', description: '韎为赤黄色皮革，古代武士甲胄的颜色，温而不燥的军旅之色'),
      ChineseColor(name: '目童子', r: 91, g: 50, b: 34, family: 'yellow', description: '瞳孔的深褐之色，古人以"目童子"称瞳仁，是观察世界的窗口'),
      ChineseColor(name: '鹰背褐', r: 143, g: 109, b: 95, family: 'yellow', description: '苍鹰背部羽毛的褐色，是猎鹰文化中最矫健的颜色'),
      ChineseColor(name: '棠梨褐', r: 149, g: 90, b: 66, family: 'yellow', description: '棠梨木纹理细密，色泽深褐，是古代雕版印刷的首选木材之色'),
      ChineseColor(name: '青骊', r: 86, g: 67, b: 23, family: 'yellow', description: '青黑色的骏马，《诗经》"驾我骐馥"，是古代良驹的名贵毛色'),
      ChineseColor(name: '赭罗', r: 154, g: 102, b: 85, family: 'yellow', description: '赭色罗纱，唐代女子夏日轻衫的颜色，薄如蝉翼的优雅'),
      ChineseColor(name: '檀褐', r: 148, g: 86, b: 53, family: 'yellow', description: '老檀木的深褐色泽，历经岁月打磨后散发的沉静光芒'),
      ChineseColor(name: '老僧衣', r: 184, g: 95, b: 68, family: 'yellow', description: '僧人袈裟经年累月洗涤后的褐色，是修行者朴素无华的精神'),
      ChineseColor(name: '朱石栗', r: 129, g: 73, b: 44, family: 'yellow', description: '朱砂与栗壳混合的深褐红，是古代漆器底色中最沉稳的一种'),
      ChineseColor(name: '紫瓯', r: 124, g: 70, b: 30, family: 'yellow', description: '紫砂壶的古称，宜兴紫砂"人间珠玉安足取，岂如阳羡溪头一丸土"'),
      ChineseColor(name: '肉红', r: 221, g: 197, b: 184, family: 'yellow', description: '如婴儿肌肤般粉嫩的淡红，是生命最初的颜色，温柔而纯真'),
      ChineseColor(name: '姜黄', r: 214, g: 197, b: 96, family: 'yellow', description: '姜黄根茎研磨的金黄色素，既是香料也是染料，是古代丝绸的常用染色'),
      ChineseColor(name: '丁香褐', r: 189, g: 150, b: 131, family: 'yellow', description: '丁香花蕾干燥后的褐色，是古代五大香料之一，芬芳而温暖'),
    ]),
    // ==================== 绿色系 ====================
    ColorFamily(id: 'green', name: '绿色系', colors: [
      ChineseColor(name: '人籁', r: 158, g: 188, b: 25, family: 'green', description: '庄子"人籁则比竹是已"，人吹竹管之声，如新竹般鲜活的黄绿'),
      ChineseColor(name: '葱倩', r: 161, g: 134, b: 80, family: 'green', description: '葱茏倩影，如远山含翠的朦胧之色，是山水画中最常见的底色'),
      ChineseColor(name: '螺青', r: 63, g: 80, b: 59, family: 'green', description: '螺壳内壁的青绿之色，古代螺钿工艺中最幽深的镶嵌色彩'),
      ChineseColor(name: '青粱', r: 195, g: 217, b: 78, family: 'green', description: '青色粟米，五谷之一，是古代农耕文明中最鲜活的丰收之色'),
      ChineseColor(name: '漆姑', r: 93, g: 131, b: 81, family: 'green', description: '漆姑草为田间野草，不起眼却生命力顽强，是乡野最朴素的绿'),
      ChineseColor(name: '春辰', r: 169, g: 190, b: 123, family: 'green', description: '春日清晨的嫩绿，万物复苏时最清新的颜色，充满生机与希望'),
      ChineseColor(name: '翠缥', r: 183, g: 211, b: 50, family: 'green', description: '翠鸟羽毛般鲜亮的黄绿，是自然界中最明快的绿色之一'),
      ChineseColor(name: '翠微', r: 76, g: 128, b: 69, family: 'green', description: '王维"翠微深处有人家"，青山深处的幽绿，是隐逸文化的颜色'),
      ChineseColor(name: '麴尘', r: 192, g: 208, b: 157, family: 'green', description: '酒曲表面的淡绿色粉末，白居易"麴尘波上春风急"的轻盈之色'),
      ChineseColor(name: '水龙吟', r: 132, g: 167, b: 41, family: 'green', description: '苏轼词牌名，"似花还似非花"的朦胧，如春水映柳的鲜绿'),
      ChineseColor(name: '芰荷', r: 79, g: 121, b: 74, family: 'green', description: '屈原"制芰荷以为衣兮"，以荷叶为衣的高洁，是楚辞中的君子之色'),
      ChineseColor(name: '欧碧', r: 192, g: 214, b: 149, family: 'green', description: '欧碧为翡翠的古称，如上等翡翠般通透的嫩绿，是珠宝中的极品'),
      ChineseColor(name: '碧山', r: 119, g: 150, b: 73, family: 'green', description: '李白"相看两不厌，只有敬亭山"，青山不老的碧绿之色'),
      ChineseColor(name: '青青', r: 79, g: 111, b: 70, family: 'green', description: '《诗经》"青青子衿，悠悠我心"，是思念之人衣领的颜色'),
      ChineseColor(name: '苍葭', r: 168, g: 191, b: 143, family: 'green', description: '《诗经》"蒹葭苍苍，白露为霜"，秋水边芦苇的苍绿之色'),
      ChineseColor(name: '石发', r: 106, g: 141, b: 82, family: 'green', description: '石上苔藓如发丝般生长，是岁月在石头上留下的绿色印记'),
      ChineseColor(name: '翠虬', r: 68, g: 106, b: 55, family: 'green', description: '虬为盘曲的龙，翠虬如苍龙盘踞般深沉的墨绿，是龙文化的颜色'),
      ChineseColor(name: '兰苕', r: 168, g: 183, b: 140, family: 'green', description: '兰草嫩枝的淡绿，孔子"芝兰生于深林"，是君子品格的象征'),
      ChineseColor(name: '菉竹', r: 105, g: 142, b: 106, family: 'green', description: '《诗经》"瞻彼淇奥，绿竹猗猗"，淇水边翠竹的清雅之色'),
      ChineseColor(name: '官绿', r: 42, g: 110, b: 63, family: 'green', description: '唐代官服中六七品所用的绿色，是科举入仕的起步之色'),
      ChineseColor(name: '青玉案', r: 168, g: 176, b: 146, family: 'green', description: '辛弃疾词牌名，"众里寻他千百度"的含蓄，如青玉般温润的绿'),
      ChineseColor(name: '庭芜绿', r: 104, g: 148, b: 92, family: 'green', description: '庭院中野草蔓生的绿色，是"庭院深深深几许"的寂寥之美'),
      ChineseColor(name: '油绿', r: 93, g: 114, b: 89, family: 'green', description: '如油菜叶般浓郁发亮的绿，是江南水乡田野中最饱满的颜色'),
      ChineseColor(name: '碧滋', r: 144, g: 160, b: 125, family: 'green', description: '碧色滋长，如雨后草木焕发的新绿，是大地最蓬勃的生命力'),
      ChineseColor(name: '莓莓', r: 78, g: 101, b: 72, family: 'green', description: '《诗经》"葛之覃兮，施于中谷，维叶莓莓"，葛藤叶茂的深绿'),
      ChineseColor(name: '瓷秘', r: 179, g: 192, b: 157, family: 'green', description: '秘色瓷为五代越窑极品，"九秋风露越窑开，夺得千峰翠色来"'),
      ChineseColor(name: '青楸', r: 129, g: 163, b: 128, family: 'green', description: '楸树叶的青绿之色，古代以楸木制棋盘，"楸枰"即棋盘的雅称'),
      ChineseColor(name: '筠雾', r: 213, g: 209, b: 174, family: 'green', description: '竹林晨雾中的朦胧之色，筠为竹皮，是竹文化中最诗意的意象'),
      ChineseColor(name: '行香子', r: 191, g: 185, b: 156, family: 'green', description: '苏轼词牌名，"清夜无尘，月色如银"，如月下竹林的清幽之色'),
      ChineseColor(name: '缥碧', r: 128, g: 164, b: 146, family: 'green', description: '吴均"水皆缥碧，千丈见底"，富春江水的清澈碧绿'),
      ChineseColor(name: '鸣珂', r: 195, g: 181, b: 156, family: 'green', description: '珂为白色美石，马饰鸣珂声声，是唐代长安街头贵族出行的排场'),
      ChineseColor(name: '琬琰', r: 169, g: 168, b: 134, family: 'green', description: '琬琰为美玉之名，《楚辞》"怀琬琰之华英"，是屈原理想的象征'),
      ChineseColor(name: '翠涛', r: 129, g: 157, b: 142, family: 'green', description: '如翠色波涛般起伏的绿，是竹海风起时万竿翠竹的壮观之色'),
      ChineseColor(name: '出岫', r: 169, g: 167, b: 115, family: 'green', description: '陶渊明"云无心以出岫"，白云从山间飘出的悠然，是归隐的颜色'),
      ChineseColor(name: '王刍', r: 169, g: 159, b: 112, family: 'green', description: '王刍为古代染草，可染黄绿之色，是最早的植物染料之一'),
      ChineseColor(name: '青梅', r: 119, g: 138, b: 119, family: 'green', description: '李白"郎骑竹马来，绕床弄青梅"，青梅竹马的纯真记忆之色'),
      ChineseColor(name: '春碧', r: 157, g: 157, b: 130, family: 'green', description: '春日碧空下万物初醒的柔和绿意，是一年中最温柔的季节之色'),
      ChineseColor(name: '执大象', r: 145, g: 145, b: 119, family: 'green', description: '老子"执大象，天下往"，大道无形的朴素之色，是道家哲学的底色'),
      ChineseColor(name: '雀梅', r: 120, g: 138, b: 111, family: 'green', description: '雀梅为盆景名木，枝干苍劲叶色青翠，是文人案头的微缩山林'),
      ChineseColor(name: '青圭', r: 146, g: 144, b: 83, family: 'green', description: '圭为古代玉制礼器，青圭用于祭祀东方，是春天与生长的象征'),
      ChineseColor(name: '绿沈', r: 147, g: 143, b: 76, family: 'green', description: '绿沈为深绿色漆器之色，唐代"绿沈枪"即以此色漆涂的名枪'),
      ChineseColor(name: '苔古', r: 121, g: 131, b: 108, family: 'green', description: '古苔覆石的幽绿，刘禹锡"苔痕上阶绿，草色入帘青"的雅致'),
      ChineseColor(name: '风入松', r: 134, g: 140, b: 78, family: 'green', description: '吴文英词牌名，松风入耳的清幽，如松针般深沉的黄绿之色'),
      ChineseColor(name: '荩箧', r: 135, g: 125, b: 82, family: 'green', description: '荩草编织的箱箧之色，古代以荩草染黄绿，是最朴素的收纳之色'),
      ChineseColor(name: '蕉月', r: 134, g: 144, b: 138, family: 'green', description: '月光透过芭蕉叶的清冷绿意，"芭蕉不展丁香结"的幽怨之美'),
      ChineseColor(name: '绞衣', r: 127, g: 117, b: 76, family: 'green', description: '绞缬为古代扎染工艺，以绳绞扎后染色，是民间染织的智慧结晶'),
      ChineseColor(name: '素綦', r: 89, g: 83, b: 51, family: 'green', description: '綦为苍灰色，素綦即朴素的灰绿，是古代平民衣着的常见之色'),
      ChineseColor(name: '千山翠', r: 120, g: 125, b: 115, family: 'green', description: '千山万壑的苍翠之色，"千山鸟飞绝"的辽阔与寂静'),
      ChineseColor(name: '天缥', r: 213, g: 235, b: 225, family: 'green', description: '天空最淡的青色，如薄纱般轻盈的天际之色，是晴日最高远的颜色'),
      ChineseColor(name: '卵色', r: 213, g: 227, b: 212, family: 'green', description: '鸟卵壳的淡青绿色，是新生命孕育时最温柔的保护色'),
      ChineseColor(name: '翕艴', r: 118, g: 118, b: 106, family: 'green', description: '翕为收敛，艴为变色，如秋叶将落未落时的灰绿，是季节交替的颜色'),
      ChineseColor(name: '沧浪', r: 177, g: 213, b: 200, family: 'green', description: '屈原"沧浪之水清兮，可以濯吾缨"，清澈溪水的碧绿之色'),
      ChineseColor(name: '葭菼', r: 202, g: 215, b: 197, family: 'green', description: '葭菼为初生的芦苇，嫩绿如玉，是水边最柔软的春色'),
      ChineseColor(name: '结绿', r: 85, g: 95, b: 77, family: 'green', description: '结绿为古代名玉，《战国策》中价值连城的宝玉之色'),
      ChineseColor(name: '山岚', r: 190, g: 210, b: 187, family: 'green', description: '山间雾气弥漫的淡绿，是中国山水画中最常见的远山之色'),
      ChineseColor(name: '冰台', r: 190, g: 202, b: 183, family: 'green', description: '冰台即艾草的别名，端午悬艾驱邪的传统，是民俗文化的绿色'),
      ChineseColor(name: '绿云', r: 73, g: 67, b: 61, family: 'green', description: '古代以"绿云"喻女子乌黑秀发，杜牧"绿云扰扰"的如墨青丝'),
      ChineseColor(name: '青古', r: 179, g: 189, b: 169, family: 'green', description: '古铜器上青绿色的铜锈，是时间在青铜上留下的美丽痕迹'),
      ChineseColor(name: '醾酴', r: 166, g: 186, b: 177, family: 'green', description: '酴醾为晚春之花，花开则春尽，是"开到荼蘼花事了"的惆怅之色'),
      ChineseColor(name: '二绿', r: 99, g: 163, b: 157, family: 'green', description: '国画颜料中的二绿，由孔雀石研磨而成，是青绿山水画的灵魂之色'),
      ChineseColor(name: '苍筤', r: 155, g: 188, b: 172, family: 'green', description: '苍筤为初生之竹，嫩绿带青，是竹林中最有生命力的新生之色'),
      ChineseColor(name: '渌波', r: 155, g: 180, b: 150, family: 'green', description: '清澈的绿色水波，谢朓"余霞散成绮，澄江静如练"的江水之色'),
      ChineseColor(name: '繐辖', r: 136, g: 191, b: 184, family: 'green', description: '繐为细葛布，辖为车轴零件，此色如古代马车帷幔的青绿之色'),
      ChineseColor(name: '铜青', r: 61, g: 142, b: 134, family: 'green', description: '铜器氧化后的青绿色，是青铜时代留给后世最美的时间印记'),
      ChineseColor(name: '青臒', r: 50, g: 113, b: 117, family: 'green', description: '臒为瘦削，青臒如深山幽谷中清瘦的溪水之色，冷冽而清澈'),
      ChineseColor(name: '耀色', r: 34, g: 107, b: 104, family: 'green', description: '耀州窑青瓷的釉色，宋代名窑之一，"巧如范金，精比琢玉"'),
      ChineseColor(name: '石绿', r: 32, g: 104, b: 100, family: 'green', description: '孔雀石研磨的绿色颜料，敦煌壁画中千年不褪的翠绿之色'),
      ChineseColor(name: '竹月', r: 127, g: 159, b: 175, family: 'green', description: '月光穿过竹林的清冷蓝绿，是"竹影横斜水清浅"的幽静之美'),
      ChineseColor(name: '月白', r: 212, g: 229, b: 239, family: 'green', description: '月光映照下的淡蓝白色，并非纯白而是带着月色的清冷，是最诗意的白'),
      ChineseColor(name: '素采', r: 212, g: 221, b: 225, family: 'green', description: '素为白色，采为光彩，素采即朴素的光华，是"大音希声"的淡雅'),
      ChineseColor(name: '星郎', r: 188, g: 212, b: 231, family: 'green', description: '星光下少年郎的清朗之色，如"星垂平野阔"的辽远与明净'),
      ChineseColor(name: '影青', r: 189, g: 203, b: 210, family: 'green', description: '景德镇影青瓷的釉色，釉面如冰似玉，光照下隐约泛青'),
      ChineseColor(name: '逍遥游', r: 178, g: 191, b: 195, family: 'green', description: '庄子《逍遥游》"北冥有鱼，其名为鲲"，如鲲鹏翱翔天际的自在'),
      ChineseColor(name: '白青', r: 152, g: 182, b: 194, family: 'green', description: '白中泛青的矿物颜色，《本草纲目》记载的铜矿石之色'),
      ChineseColor(name: '青鸾', r: 154, g: 167, b: 177, family: 'green', description: '青鸾为传说中的神鸟，西王母的信使，此色如鸾鸟羽翼的青灰'),
      ChineseColor(name: '东方既白', r: 139, g: 163, b: 199, family: 'green', description: '苏轼《赤壁赋》"不知东方之既白"，黎明前天际最初的蓝光'),
      ChineseColor(name: '秋蓝', r: 125, g: 146, b: 159, family: 'green', description: '秋日天空的深蓝，"天高云淡，望断南飞雁"的辽阔与清朗'),
      ChineseColor(name: '空青', r: 102, g: 136, b: 158, family: 'green', description: '空青为中空的铜矿石，内含碧水，古人视为明目良药与珍贵颜料'),
      ChineseColor(name: '太师青', r: 84, g: 118, b: 137, family: 'green', description: '太师椅常用的深青色漆面，是明清官宦人家厅堂的庄重之色'),
      ChineseColor(name: '菘蓝', r: 107, g: 121, b: 142, family: 'green', description: '菘蓝即板蓝根的植物来源，叶可入药，根可染蓝，药食同源的智慧'),
      ChineseColor(name: '育阳染', r: 87, g: 100, b: 112, family: 'green', description: '育阳为古代染色重镇，以精湛的蓝染技艺闻名，是匠人精神的颜色'),
      ChineseColor(name: '青雀头黛', r: 53, g: 78, b: 107, family: 'green', description: '以青雀头部羽毛色制成的画眉之黛，是古代女子最精致的眉妆之色'),
      ChineseColor(name: '霁蓝', r: 68, g: 70, b: 84, family: 'green', description: '雨后初晴的深蓝釉色，明代御窑极品，与霁红并称瓷器双绝'),
      ChineseColor(name: '瑾瑜', r: 30, g: 39, b: 85, family: 'green', description: '瑾瑜皆为美玉，《楚辞》"怀瑾握瑜兮"，是屈原高洁品格的象征'),
      ChineseColor(name: '缟羽', r: 239, g: 239, b: 239, family: 'green', description: '白鹤羽毛的纯白之色，"晴空一鹤排云上"的高洁与超然'),
    ]),
    // ==================== 蓝色系 ====================
    ColorFamily(id: 'blue', name: '蓝色系', colors: [
      ChineseColor(name: '佛头青', r: 25, g: 65, b: 95, family: 'blue', description: '佛像头部螺发所用的深蓝色颜料，敦煌石窟中最庄严的佛像之色'),
      ChineseColor(name: '青黛', r: 69, g: 70, b: 94, family: 'blue', description: '蓝草提取的深青色颜料，既是画眉之黛也是中药，"青黛画眉红锦靴"'),
      ChineseColor(name: '西子', r: 135, g: 192, b: 202, family: 'blue', description: '苏轼"欲把西湖比西子"，西湖水色如西施般清丽动人的碧蓝'),
      ChineseColor(name: '骐驎', r: 18, g: 38, b: 79, family: 'blue', description: '骐驎即麒麟，传说中的仁兽，此色如夜空中麒麟奔腾的深邃蓝黑'),
      ChineseColor(name: '黲艴', r: 69, g: 70, b: 89, family: 'blue', description: '黲为暗淡，艴为变色，如暮色四合时天际最后的深蓝'),
      ChineseColor(name: '正青', r: 108, g: 168, b: 175, family: 'blue', description: '五正色之一的青，《周礼》中东方之色，代表春天与生长'),
      ChineseColor(name: '花青', r: 28, g: 40, b: 71, family: 'blue', description: '国画颜料中的花青，由蓝靛提取，是水墨画中最重要的蓝色'),
      ChineseColor(name: '璆琳', r: 52, g: 48, b: 66, family: 'blue', description: '璆琳为美玉之名，《山海经》中昆仑山上的神玉，深邃如夜空'),
      ChineseColor(name: '扁青', r: 80, g: 146, b: 150, family: 'blue', description: '扁青即蓝铜矿，古代重要的蓝色颜料来源，壁画中的天空之色'),
      ChineseColor(name: '优昙瑞', r: 97, g: 94, b: 168, family: 'blue', description: '优昙花三千年一开，佛经中的祥瑞之花，此色如佛光中的紫蓝'),
      ChineseColor(name: '绀蝶', r: 44, g: 47, b: 59, family: 'blue', description: '绀为深青带红，如夜间蝴蝶翅膀的幽暗蓝紫，神秘而美丽'),
      ChineseColor(name: '法翠', r: 161, g: 139, b: 150, family: 'blue', description: '佛法如翠玉般珍贵，此色如寺院中古佛前供奉的翠玉之色'),
      ChineseColor(name: '暮山紫', r: 164, g: 171, b: 214, family: 'blue', description: '王勃"烟光凝而暮山紫"，傍晚远山笼罩在紫蓝色烟霭中的壮美'),
      ChineseColor(name: '獭见', r: 21, g: 29, b: 41, family: 'blue', description: '水獭捕鱼后陈列岸边如祭祀，"獭祭鱼"是古代物候的标志，此色如深水'),
      ChineseColor(name: '吐绶蓝', r: 65, g: 130, b: 164, family: 'blue', description: '吐绶鸡颈部的鲜蓝色肉垂，是自然界中最惊艳的蓝色之一'),
      ChineseColor(name: '紫苑', r: 117, g: 124, b: 187, family: 'blue', description: '紫苑花秋日盛开，是重阳节前后最常见的蓝紫色野花'),
      ChineseColor(name: '天水碧', r: 90, g: 164, b: 174, family: 'blue', description: '五代后蜀孟昶妃子所创的染色，如天光映水的碧蓝，是蜀锦名色'),
      ChineseColor(name: '鱼师青', r: 50, g: 120, b: 138, family: 'blue', description: '鱼师即鲨鱼皮，古代以鲨鱼皮装饰刀剑，此色如鲨皮的青灰蓝'),
      ChineseColor(name: '延维', r: 74, g: 75, b: 157, family: 'blue', description: '延维为上古神蛇，人首蛇身，此色如神蛇鳞片的幽蓝光泽'),
      ChineseColor(name: '天井', r: 164, g: 201, b: 204, family: 'blue', description: '徽派建筑天井中仰望天空的颜色，四水归堂的建筑智慧之色'),
      ChineseColor(name: '软翠', r: 109, g: 108, b: 135, family: 'blue', description: '如软玉般温润的翠蓝，是宋代汝窑"雨过天青云破处"的意境'),
      ChineseColor(name: '曾青', r: 83, g: 81, b: 100, family: 'blue', description: '曾青为层状铜矿石，《神农本草经》上品药材，也是古代蓝色颜料'),
      ChineseColor(name: '云门', r: 162, g: 210, b: 226, family: 'blue', description: '黄帝所作六大乐舞之一《云门》，如祥云初开时天际的明蓝'),
      ChineseColor(name: '青绹', r: 74, g: 75, b: 82, family: 'blue', description: '绹为丝绳，青绹即青色丝绳，古代系玉佩的丝带之色'),
      ChineseColor(name: '螺子黛', r: 19, g: 57, b: 86, family: 'blue', description: '波斯进贡的珍贵画眉颜料，唐代宫廷专用，"螺子黛"价值千金'),
      ChineseColor(name: '群青', r: 46, g: 89, b: 167, family: 'blue', description: '由青金石研磨而成的珍贵蓝色颜料，比黄金还贵，是壁画中天空的颜色'),
      ChineseColor(name: '监德', r: 111, g: 148, b: 205, family: 'blue', description: '监为明察，德为品行，此色如青天白日般明朗，是公正廉明的象征'),
      ChineseColor(name: '苍苍', r: 89, g: 118, b: 186, family: 'blue', description: '《诗经》"蒹葭苍苍"，也指苍天之色，"天苍苍，野茫茫"的辽阔'),
      ChineseColor(name: '孔雀蓝', r: 73, g: 148, b: 196, family: 'blue', description: '孔雀羽毛中最璀璨的蓝色，也是景德镇名贵釉色，华丽而高贵'),
      ChineseColor(name: '青冥', r: 50, g: 113, b: 174, family: 'blue', description: '李白"青冥浩荡不见底"，高远深邃的天空之色，是诗仙的浪漫'),
      ChineseColor(name: '柔蓝', r: 116, g: 104, b: 152, family: 'blue', description: '如蓝色丝绸般柔软的紫蓝，是闺阁中最温柔的帷幔之色'),
      ChineseColor(name: '碧城', r: 118, g: 80, b: 123, family: 'blue', description: '李商隐"碧城十二曲阑干"，仙境中的碧玉之城，神秘而幽远'),
      ChineseColor(name: '蓝采和', r: 86, g: 67, b: 111, family: 'blue', description: '八仙之一蓝采和，手持花篮踏歌而行，此色如其蓝衫的洒脱'),
      ChineseColor(name: '绀宇', r: 101, g: 81, b: 116, family: 'blue', description: '绀宇即佛寺，佛寺屋顶的深蓝紫色琉璃瓦，是佛门清净之地的颜色'),
      ChineseColor(name: '帝释青', r: 10, g: 52, b: 96, family: 'blue', description: '帝释天为佛教护法神，此色如帝释天宫殿的深邃蓝色，庄严而神圣'),
      ChineseColor(name: '碧落', r: 174, g: 208, b: 238, family: 'blue', description: '白居易"上穷碧落下黄泉"，碧落即天空最高处，是最辽远的蓝'),
      ChineseColor(name: '晴山', r: 163, g: 187, b: 219, family: 'blue', description: '晴日远山的淡蓝之色，"山色空蒙雨亦奇"的对面——晴日的明朗'),
      ChineseColor(name: '品月', r: 138, g: 171, b: 204, family: 'blue', description: '品评月色的雅趣，此色如中秋月光映照下的淡蓝天幕'),
      ChineseColor(name: '窃蓝', r: 136, g: 171, b: 218, family: 'blue', description: '窃为浅淡之意，窃蓝即浅蓝，如初春天空最清澈的蓝'),
      ChineseColor(name: '授蓝', r: 115, g: 155, b: 197, family: 'blue', description: '蓝染工艺中第一道浸染的浅蓝，是靛蓝染色技艺的起始之色'),
      ChineseColor(name: '玄校', r: 169, g: 160, b: 130, family: 'blue', description: '玄为黑色，校为木栏，古代学宫围栏的深褐之色，是求学之地的庄重'),
      ChineseColor(name: '黄琮', r: 158, g: 140, b: 107, family: 'blue', description: '琮为方形玉器，以黄琮祭地，是古代六器之一，承载天圆地方的宇宙观'),
      ChineseColor(name: '石莲褐', r: 146, g: 137, b: 123, family: 'blue', description: '石莲花叶片的灰褐之色，多肉植物中最古朴的品种之色'),
      ChineseColor(name: '绿豆褐', r: 146, g: 137, b: 107, family: 'blue', description: '绿豆皮的褐绿之色，"绿豆汤"是民间消暑的传统饮品之色'),
      ChineseColor(name: '猠绶', r: 117, g: 108, b: 75, family: 'blue', description: '猠为小鹿，绶为丝带，如小鹿身上斑纹的褐色，是山林的灵动'),
      ChineseColor(name: '茶色', r: 136, g: 118, b: 87, family: 'blue', description: '陆羽《茶经》中上品茶汤之色，"茶者，南方之嘉木也"的温润'),
      ChineseColor(name: '濯绛', r: 121, g: 104, b: 96, family: 'blue', description: '濯为洗涤，绛为深红，洗褪后的绛色变为温和的灰褐，岁月的痕迹'),
      ChineseColor(name: '黑朱', r: 112, g: 105, b: 93, family: 'blue', description: '朱漆经年累月氧化变暗的颜色，是古建筑上时间沉淀的印记'),
      ChineseColor(name: '冥色', r: 102, g: 95, b: 77, family: 'blue', description: '天色将暮未暮的昏暗之色，"暮色苍茫看劲松"的沉静时刻'),
      ChineseColor(name: '伽罗', r: 109, g: 92, b: 86, family: 'blue', description: '伽罗为沉香中的极品，产自越南，燃烧时香气清幽，一克千金'),
      ChineseColor(name: '苍艾', r: 68, g: 67, b: 59, family: 'blue', description: '陈年艾草的苍褐之色，三年之艾方可入药，是中医灸法的根本'),
    ]),
    // ==================== 紫色系 ====================
    ColorFamily(id: 'purple', name: '紫色系', colors: [
      ChineseColor(name: '紫蒲', r: 166, g: 85, b: 157, family: 'purple', description: '蒲草花穗泛紫的颜色，端午节编蒲为剑悬于门上以驱邪避祟'),
      ChineseColor(name: '香炉紫烟', r: 211, g: 204, b: 214, family: 'purple', description: '李白"日照香炉生紫烟"，庐山瀑布前阳光折射水雾的梦幻紫色'),
      ChineseColor(name: '鸦雏', r: 106, g: 91, b: 109, family: 'purple', description: '小乌鸦羽毛的紫黑之色，古代以"鸦雏色"形容女子乌黑的秀发'),
      ChineseColor(name: '紫紶', r: 125, g: 68, b: 132, family: 'purple', description: '紶为丝织品的花纹，紫紶即紫色织锦的华美纹样之色'),
      ChineseColor(name: '苍烟落照', r: 125, g: 68, b: 132, family: 'purple', description: '夕阳西下时苍茫烟霭中的紫色余晖，是一天中最诗意的时刻'),
      ChineseColor(name: '玄天', r: 67, g: 84, b: 88, family: 'purple', description: '玄天上帝即真武大帝，道教北方之神，此色如北方夜空的深邃'),
      ChineseColor(name: '拂紫绵', r: 126, g: 82, b: 127, family: 'purple', description: '轻拂紫色丝绵的柔软触感，是古代贵族冬衣中最奢华的填充之色'),
      ChineseColor(name: '甘石', r: 189, g: 178, b: 178, family: 'purple', description: '甘石即炉甘石，中药外用良药，也是古代炼锌的矿石之色'),
      ChineseColor(name: '烟墨', r: 82, g: 97, b: 85, family: 'purple', description: '松烟制墨的深灰之色，"磨墨如病夫"的耐心，是书法艺术的根基'),
      ChineseColor(name: '频紫', r: 138, g: 24, b: 116, family: 'purple', description: '频为频繁，紫为尊贵，"紫气频来"是祥瑞之兆，此色浓烈而高贵'),
      ChineseColor(name: '紫莳', r: 156, g: 142, b: 169, family: 'purple', description: '莳为种植，紫莳如精心培育的紫藤花色，是园林中最优雅的攀援之美'),
      ChineseColor(name: '紫鼠', r: 89, g: 76, b: 87, family: 'purple', description: '紫貂皮毛的深紫灰色，是古代北方贡品中最珍贵的皮草之色'),
      ChineseColor(name: '三公子', r: 102, g: 61, b: 116, family: 'purple', description: '牡丹品种名，花色深紫如贵族公子的华服，是洛阳花会的名品'),
      ChineseColor(name: '银褐', r: 156, g: 141, b: 155, family: 'purple', description: '银灰与褐色交融的温和之色，如老银器上岁月留下的柔和光泽'),
      ChineseColor(name: '栀子', r: 250, g: 192, b: 81, family: 'purple', description: '栀子花果实可提取黄色染料，是古代最常用的天然黄色染料之一'),
      ChineseColor(name: '齐紫', r: 108, g: 33, b: 109, family: 'purple', description: '春秋时齐桓公好紫衣，举国效仿，"齐紫"成为时尚潮流的代名词'),
      ChineseColor(name: '藕丝褐', r: 168, g: 135, b: 135, family: 'purple', description: '莲藕丝般细腻的褐色，"藕断丝连"的缠绵之色'),
      ChineseColor(name: '黄白游', r: 255, g: 247, b: 153, family: 'purple', description: '道教炼丹术语，黄白即金银，"黄白游"是炼金术的理想之色'),
      ChineseColor(name: '凝夜紫', r: 66, g: 34, b: 86, family: 'purple', description: '李贺"黑云压城城欲摧，甲光向日金鳞开"，夜色凝结的深紫'),
      ChineseColor(name: '烟红', r: 157, g: 133, b: 143, family: 'purple', description: '如烟雾笼罩下的淡红，是"烟笼寒水月笼沙"的朦胧之美'),
      ChineseColor(name: '松花', r: 255, g: 238, b: 111, family: 'purple', description: '松树花粉的鲜黄之色，松花蛋即以此色命名，是民间饮食的智慧'),
      ChineseColor(name: '石英', r: 200, g: 182, b: 187, family: 'purple', description: '石英矿物的淡紫灰色，是地壳中最常见的矿物，朴素而坚韧'),
      ChineseColor(name: '迷楼灰', r: 145, g: 130, b: 143, family: 'purple', description: '隋炀帝所建迷楼的灰紫之色，"迷楼"是奢靡与覆灭的历史警示'),
      ChineseColor(name: '缃叶', r: 236, g: 212, b: 82, family: 'purple', description: '缃为浅黄色，缃叶即泛黄的书页之色，是古籍善本的岁月之色'),
      ChineseColor(name: '红藤杖', r: 146, g: 129, b: 135, family: 'purple', description: '红藤制成的手杖之色，是古代文人出行的雅物，也是长者的倚靠'),
    ]),
    // ==================== 白灰色系 ====================
    ColorFamily(id: 'neutral', name: '白灰色系', colors: [
      ChineseColor(name: '山矾', r: 245, g: 243, b: 242, family: 'neutral', description: '山矾花洁白如雪，黄庭坚以此花名代替"郑花"之俗称，是文人的雅趣'),
      ChineseColor(name: '藕丝秋半', r: 211, g: 203, b: 197, family: 'neutral', description: '秋日莲藕丝的淡灰白色，如秋意渐浓时荷塘的萧瑟之美'),
      ChineseColor(name: '溶溶月', r: 190, g: 194, b: 188, family: 'neutral', description: '杜牧"烟笼寒水月笼沙"，月光溶溶如水的柔和银灰之色'),
      ChineseColor(name: '浅云', r: 234, g: 235, b: 241, family: 'neutral', description: '天边最薄的云层之色，如轻纱般飘渺，是天空最温柔的装饰'),
      ChineseColor(name: '云母', r: 178, g: 190, b: 177, family: 'neutral', description: '云母矿物的银灰光泽，古代用于窗户装饰，"云母屏风烛影深"'),
      ChineseColor(name: '月魄', r: 178, g: 182, b: 182, family: 'neutral', description: '月亮的精魄之色，古人认为月中有魄，此色如月光般清冷素净'),
      ChineseColor(name: '凝脂', r: 245, g: 242, b: 233, family: 'neutral', description: '白居易"温泉水滑洗凝脂"，如凝固的羊脂般温润的乳白之色'),
      ChineseColor(name: '爨白', r: 246, g: 249, b: 228, family: 'neutral', description: '爨为灶台，爨白即灶台烟火熏染后的暖白，是人间烟火的温度'),
      ChineseColor(name: '冻缥', r: 190, g: 194, b: 179, family: 'neutral', description: '缥为淡青丝帛，冻缥如冰冻后的淡青白色，是冬日最清冷的素色'),
      ChineseColor(name: '皦玉', r: 235, g: 238, b: 232, family: 'neutral', description: '皦为洁白明亮，皦玉即最纯净的白玉之色，"白璧无瑕"的理想'),
      ChineseColor(name: '吉量', r: 235, g: 237, b: 223, family: 'neutral', description: '吉量为周穆王八骏之一，白色骏马的毛色，是速度与力量的象征'),
      ChineseColor(name: '草白', r: 191, g: 193, b: 169, family: 'neutral', description: '秋草枯白时的颜色，"离离原上草，一岁一枯荣"的自然轮回'),
      ChineseColor(name: '玉頩', r: 234, g: 229, b: 227, family: 'neutral', description: '頩为面色美好，玉頩如美玉般的面容之色，是古代美人的肤色赞美'),
      ChineseColor(name: '天球', r: 224, g: 223, b: 198, family: 'neutral', description: '天球为传说中的神玉，《尚书》中周武王的镇国之宝'),
      ChineseColor(name: '不皂', r: 167, g: 170, b: 161, family: 'neutral', description: '皂为黑色，不皂即非黑非白的灰色，"不分皂白"典故的本色'),
      ChineseColor(name: '二目鱼', r: 223, g: 224, b: 217, family: 'neutral', description: '比目鱼的银白之色，古人以比目鱼喻夫妻相伴，是忠贞的象征'),
      ChineseColor(name: '霜地', r: 199, g: 198, b: 182, family: 'neutral', description: '秋霜覆盖大地的银白之色，"霜叶红于二月花"前的清冷底色'),
      ChineseColor(name: '绍衣', r: 168, g: 161, b: 156, family: 'neutral', description: '绍为继承，绍衣即承继先人衣钵的素色，是传承与敬意的颜色'),
      ChineseColor(name: '韶粉', r: 224, g: 224, b: 208, family: 'neutral', description: '韶为美好，韶粉如青春年华般明亮的粉白，是少女最纯真的颜色'),
      ChineseColor(name: '余白', r: 201, g: 207, b: 193, family: 'neutral', description: '画面留白处的余韵之色，中国画"计白当黑"的美学智慧'),
      ChineseColor(name: '雷雨垂', r: 122, g: 123, b: 120, family: 'neutral', description: '雷雨将至时天空低垂的铅灰之色，"山雨欲来风满楼"的压迫感'),
      ChineseColor(name: '香皮', r: 216, g: 209, b: 197, family: 'neutral', description: '沉香木外皮的淡灰白色，剥去外皮方见内里的芬芳，是含蓄之美'),
      ChineseColor(name: '墨黪', r: 88, g: 82, b: 72, family: 'neutral', description: '黪为浅黑色，墨黪如淡墨般的深灰，是书法中"枯笔"的颜色'),
      ChineseColor(name: '石涅', r: 104, g: 106, b: 103, family: 'neutral', description: '涅为黑色染料，"涅而不缁"出自《论语》，喻品格高洁不受污染'),
      ChineseColor(name: '明月珰', r: 212, g: 211, b: 202, family: 'neutral', description: '明月珰为汉代耳饰，以明月珠制成，此色如珠光般温润的银白'),
    ]),
  ];

  static List<ChineseColor> get allColors =>
      families.expand((f) => f.colors).toList();

  static List<ColorFamily> get sortedFamilies {
    return families.map((family) {
      final result = sortFamilyIntoColumns(family);
      return ColorFamily(id: family.id, name: family.name, colors: result.colors);
    }).toList();
  }

  static ({List<ChineseColor> colors, List<int> columnLengths}) sortFamilyIntoColumns(ColorFamily family) {
    final colors = List<ChineseColor>.from(family.colors);
    if (colors.length <= 3) {
      return (colors: colors, columnLengths: [colors.length]);
    }

    final withHsl = colors.map((c) {
      final hsl = HSLColor.fromColor(Color.fromARGB(255, c.r, c.g, c.b));
      return (color: c, hsl: hsl);
    }).toList();

    const hueBucketSize = 20.0;
    const satThreshold = 0.10;
    
    final Map<int, List<({ChineseColor color, HSLColor hsl})>> buckets = {};
    const grayBucket = -1;
    
    for (final item in withHsl) {
      int bucket;
      if (item.hsl.saturation < satThreshold) {
        bucket = grayBucket;
      } else {
        bucket = (item.hsl.hue / hueBucketSize).floor();
      }
      buckets.putIfAbsent(bucket, () => []);
      buckets[bucket]!.add(item);
    }

    final sortedKeys = buckets.keys.where((k) => k != grayBucket).toList()..sort();
    final mergedBuckets = <int, List<({ChineseColor color, HSLColor hsl})>>{};
    
    for (final key in sortedKeys) {
      final items = buckets[key]!;
      if (items.length == 1 && mergedBuckets.isNotEmpty) {
        final lastKey = mergedBuckets.keys.last;
        mergedBuckets[lastKey]!.addAll(items);
      } else {
        mergedBuckets[key] = List.from(items);
      }
    }
    
    if (buckets.containsKey(grayBucket) && buckets[grayBucket]!.isNotEmpty) {
      mergedBuckets[grayBucket] = buckets[grayBucket]!;
    }

    const maxRowsPerCol = 8;

    final orderedKeys = mergedBuckets.keys.toList()
      ..sort((a, b) {
        if (a == grayBucket) return 1;
        if (b == grayBucket) return -1;
        return a.compareTo(b);
      });

    final sortedColors = <ChineseColor>[];
    final columnLengths = <int>[];

    for (final key in orderedKeys) {
      final items = mergedBuckets[key]!;
      items.sort((a, b) => b.hsl.lightness.compareTo(a.hsl.lightness));

      if (items.length > maxRowsPerCol) {
        final numSplits = (items.length / maxRowsPerCol).ceil();
        final baseSize = items.length ~/ numSplits;
        final remainder = items.length % numSplits;
        int offset = 0;
        for (int s = 0; s < numSplits; s++) {
          final chunkSize = baseSize + (s < remainder ? 1 : 0);
          for (int i = offset; i < offset + chunkSize; i++) {
            sortedColors.add(items[i].color);
          }
          columnLengths.add(chunkSize);
          offset += chunkSize;
        }
      } else {
        for (final item in items) {
          sortedColors.add(item.color);
        }
        columnLengths.add(items.length);
      }
    }

    _smoothColumnLengths(sortedColors, columnLengths);
    _interpolateColumns(sortedColors, columnLengths);

    return (colors: sortedColors, columnLengths: columnLengths);
  }

  static void _interpolateColumns(
      List<ChineseColor> colors, List<int> lengths) {
    if (lengths.isEmpty) return;

    final newColors = <ChineseColor>[];
    final newLengths = <int>[];
    int offset = 0;

    for (int col = 0; col < lengths.length; col++) {
      final colLen = lengths[col];
      if (colLen <= 1) {
        for (int i = offset; i < offset + colLen; i++) {
          newColors.add(colors[i]);
        }
        newLengths.add(colLen);
        offset += colLen;
        continue;
      }

      final colColors = <ChineseColor>[];
      for (int i = offset; i < offset + colLen; i++) {
        final c = colors[i];
        if (colColors.isNotEmpty) {
          final prev = colColors.last;
          final prevHsl = HSLColor.fromColor(prev.toColor());
          final curHsl = HSLColor.fromColor(c.toColor());

          final lDiff = (prevHsl.lightness - curHsl.lightness).abs();
          final sDiff = (prevHsl.saturation - curHsl.saturation).abs();
          double hDiff = (prevHsl.hue - curHsl.hue).abs();
          if (hDiff > 180) hDiff = 360 - hDiff;
          final hNorm = hDiff / 360.0;

          final totalDiff = lDiff + sDiff * 0.5 + hNorm * 0.3;

          int steps = 0;
          if (totalDiff > 0.35) {
            steps = 2;
          } else if (totalDiff > 0.18) {
            steps = 1;
          }

          for (int s = 1; s <= steps; s++) {
            final t = s / (steps + 1);
            final interpHsl = _lerpHsl(prevHsl, curHsl, t);
            final interpColor = interpHsl.toColor();
            final familyName = c.family;
            colColors.add(ChineseColor(
              name: _generateTraditionalName(interpHsl),
              r: interpColor.red,
              g: interpColor.green,
              b: interpColor.blue,
              family: familyName,
            ));
          }
        }
        colColors.add(c);
      }

      newColors.addAll(colColors);
      newLengths.add(colColors.length);
      offset += colLen;
    }

    colors.clear();
    colors.addAll(newColors);
    lengths.clear();
    lengths.addAll(newLengths);
  }

  static HSLColor _lerpHsl(HSLColor a, HSLColor b, double t) {
    double hDiff = b.hue - a.hue;
    if (hDiff > 180) hDiff -= 360;
    if (hDiff < -180) hDiff += 360;
    double h = (a.hue + hDiff * t) % 360;
    if (h < 0) h += 360;

    final s = a.saturation + (b.saturation - a.saturation) * t;
    final l = a.lightness + (b.lightness - a.lightness) * t;
    final alpha = a.alpha + (b.alpha - a.alpha) * t;

    return HSLColor.fromAHSL(
      alpha.clamp(0.0, 1.0),
      h,
      s.clamp(0.0, 1.0),
      l.clamp(0.0, 1.0),
    );
  }

  static final Set<String> _usedNames = {};

  static String _generateTraditionalName(HSLColor hsl) {
    final h = hsl.hue;
    final s = hsl.saturation;
    final l = hsl.lightness;

    if (s < 0.08) {
      return _pickUnique(_grayNames2, l);
    }

    List<String> pool;
    if (h < 15 || h >= 345) {
      pool = l < 0.35
          ? ['绛霄', '殷火', '赤壁', '朱砂', '丹枫', '赤焰', '绛云', '朱阙']
          : l < 0.55
          ? ['茜草', '彤云', '丹霞', '赬霞', '朱华', '绛帐', '赤霓', '丹桂']
          : l < 0.75
          ? ['绯樱', '桃夭', '酡颜', '霞光', '绯云', '桃溪', '霞绮', '绯帛']
          : ['粉黛', '桃腮', '霞影', '绯雪', '桃雨', '霞裳', '粉蝶', '桃笺'];
    } else if (h < 35) {
      pool = l < 0.35
          ? ['赭壁', '栗壳', '棕榈', '褐岩', '赭土', '栗鼠', '棕陶', '褐铁']
          : l < 0.55
          ? ['橘颂', '柑露', '杏坛', '橙暮', '橘洲', '柑霜', '杏雨', '橙晖']
          : l < 0.75
          ? ['琥珀', '曦光', '珀玉', '晖映', '琥珀', '曦色', '珀光', '晖暖']
          : ['杏白', '橘雪', '珀霜', '曦露', '杏霜', '橘烟', '珀影', '曦雾'];
    } else if (h < 55) {
      pool = l < 0.35
          ? ['驼绒', '秋棠', '枯叶', '焦墨', '驼峰', '秋壤', '枯荷', '焦桐']
          : l < 0.55
          ? ['藤萝', '蜡梅', '栌霜', '姜汁', '藤花', '蜡照', '栌叶', '姜桂']
          : l < 0.75
          ? ['鹅黄', '缃帙', '鸾凤', '麦浪', '鹅绒', '缃绮', '鸾镜', '麦穗']
          : ['缃云', '鹅羽', '麦光', '缃素', '鹅雪', '麦霜', '缃烟', '鹅白'];
    } else if (h < 75) {
      pool = l < 0.35
          ? ['苍耳', '暗柳', '墨竹', '黯淡', '苍梧', '暗香', '墨池', '黯然']
          : l < 0.55
          ? ['金盏', '菊裳', '蕊珠', '穗黄', '金缕', '菊泉', '蕊宫', '穗光']
          : l < 0.75
          ? ['鹂鸣', '莺啼', '粟米', '稻香', '鹂语', '莺梭', '粟金', '稻浪']
          : ['莺白', '粟霜', '稻云', '鹂雪', '莺烟', '粟光', '稻露', '鹂影'];
    } else if (h < 105) {
      pool = l < 0.35
          ? ['荫翳', '蓊郁', '郁苍', '茂林', '荫浓', '蓊蔚', '郁葱', '茂竹']
          : l < 0.55
          ? ['柳烟', '荇藻', '萍踪', '蘋风', '柳丝', '荇带', '萍水', '蘋末']
          : l < 0.75
          ? ['葱茏', '荷风', '芽绿', '萌春', '葱翠', '荷露', '芽黄', '萌芽']
          : ['荷白', '芽雪', '萌霜', '葱白', '荷烟', '芽露', '萌光', '葱雾'];
    } else if (h < 150) {
      pool = l < 0.35
          ? ['松烟', '竹沥', '苔痕', '藓壁', '松墨', '竹青', '苔衣', '藓绿']
          : l < 0.55
          ? ['翠微', '碧落', '青琅', '绿萼', '翠屏', '碧潭', '青冥', '绿漪']
          : l < 0.75
          ? ['荻花', '蒹葭', '葭月', '薄荷', '荻烟', '蒹霜', '葭露', '薄雾']
          : ['翠烟', '碧霜', '青白', '绿雪', '翠露', '碧影', '青烟', '绿云'];
    } else if (h < 195) {
      pool = l < 0.35
          ? ['鸦青', '墨池', '黛色', '玄鉴', '鸦翠', '墨玉', '黛眉', '玄武']
          : l < 0.55
          ? ['铜绿', '石青', '瓷韵', '釉彩', '铜雀', '石黛', '瓷青', '釉光']
          : l < 0.75
          ? ['沁碧', '泉鸣', '涧户', '溪光', '沁芳', '泉石', '涧碧', '溪月']
          : ['沁雪', '泉白', '涧霜', '溪烟', '沁露', '泉影', '涧云', '溪雾'];
    } else if (h < 240) {
      pool = l < 0.35
          ? ['藏青', '靛蓝', '渊默', '冥海', '藏蓝', '靛花', '渊泉', '冥色']
          : l < 0.55
          ? ['蓝田', '湛露', '澄江', '潭影', '蓝桥', '湛碧', '澄波', '潭水']
          : l < 0.75
          ? ['霁月', '晴岚', '岚光', '烟波', '霁色', '晴空', '岚翠', '烟霞']
          : ['霁雪', '晴雪', '岚烟', '烟白', '霁影', '晴霜', '岚雾', '烟云'];
    } else if (h < 285) {
      pool = l < 0.35
          ? ['紫府', '玄圃', '幽兰', '冥紫', '紫宸', '玄霜', '幽篁', '冥鸿']
          : l < 0.55
          ? ['堇色', '藿香', '蕈紫', '菫青', '堇露', '藿紫', '蕈菌', '菫花']
          : l < 0.75
          ? ['薰风', '兰芷', '芷兰', '蕙畹', '薰衣', '兰蕙', '芷若', '蕙风']
          : ['薰雪', '兰雪', '芷白', '蕙霜', '薰烟', '兰烟', '芷露', '蕙影'];
    } else {
      pool = l < 0.35
          ? ['酱紫', '檀香', '梅萼', '枣泥', '酱褐', '檀木', '梅子', '枣红']
          : l < 0.55
          ? ['蔷薇', '薇露', '芍药', '葵紫', '蔷靡', '薇紫', '芍红', '葵花']
          : l < 0.75
          ? ['瑰丽', '瑶光', '琼华', '珊瑚', '瑰紫', '瑶池', '琼枝', '珊影']
          : ['瑰雪', '瑶霜', '琼露', '珊白', '瑰烟', '瑶影', '琼雾', '珊烟'];
    }

    for (final name in pool) {
      if (!_usedNames.contains(name)) {
        _usedNames.add(name);
        return name;
      }
    }

    final baseParts = pool.isNotEmpty ? pool.first : '无名';
    final suffixes = ['吟', '引', '令', '赋', '曲', '调', '韵', '意'];
    for (final suf in suffixes) {
      final name = '${baseParts.substring(0, 1)}$suf';
      if (!_usedNames.contains(name)) {
        _usedNames.add(name);
        return name;
      }
    }

    return pool.isNotEmpty ? pool.first : '过渡';
  }

  static final _rng = _SimpleRng();

  static String _pickFromList(List<String> list) {
    return list[_rng.next() % list.length];
  }

  static String _pickUnique(List<String> list, double lightness) {
    final idx = (lightness * (list.length - 1)).round().clamp(0, list.length - 1);
    final name = list[idx];
    if (!_usedNames.contains(name)) {
      _usedNames.add(name);
      return name;
    }
    for (final n in list) {
      if (!_usedNames.contains(n)) {
        _usedNames.add(n);
        return n;
      }
    }
    return '$name色';
  }

  static const _grayNames2 = [
    '玄冥', '黝堂', '黯淡', '墨池', '缁衣', '皂角', '铅华', '灰阑',
    '银汉', '素练', '缟素', '霜华', '雪霁', '月华', '霰雪', '皓月',
    '玄鉴', '黝黑', '墨色', '缁尘', '铅灰', '灰蝶', '银霜', '素月',
  ];

  static void _smoothColumnLengths(
      List<ChineseColor> colors, List<int> lengths) {
    if (lengths.length < 2) return;

    const maxDiff = 2;
    bool changed = true;
    int iterations = 0;

    while (changed && iterations < 5) {
      changed = false;
      iterations++;

      for (int i = 0; i < lengths.length - 1; i++) {
        final diff = lengths[i] - lengths[i + 1];
        if (diff > maxDiff) {
          final moveCount = (diff - maxDiff + 1) ~/ 2;
          for (int m = 0; m < moveCount; m++) {
            int colIEnd = 0;
            for (int c = 0; c <= i; c++) {
              colIEnd += lengths[c];
            }
            if (colIEnd > 0 && colIEnd <= colors.length) {
              final color = colors.removeAt(colIEnd - 1);
              colors.insert(colIEnd, color);
              lengths[i]--;
              lengths[i + 1]++;
              changed = true;
            }
          }
        } else if (diff < -maxDiff) {
          final moveCount = (-diff - maxDiff + 1) ~/ 2;
          for (int m = 0; m < moveCount; m++) {
            int colIEnd = 0;
            for (int c = 0; c <= i; c++) {
              colIEnd += lengths[c];
            }
            if (colIEnd < colors.length) {
              final color = colors.removeAt(colIEnd);
              colors.insert(colIEnd, color);
              lengths[i]++;
              lengths[i + 1]--;
              changed = true;
            }
          }
        }
      }
    }
  }
}

/// 简单确定性伪随机
class _SimpleRng {
  int _state = 42;
  int next() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state;
  }
}
