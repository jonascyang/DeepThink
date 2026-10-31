// Generated from https://github.com/bitcoin/bips/tree/master/bip-0039
// english.txt sha256 2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda
// chinese_simplified.txt sha256 5c5942792bd8340cb8b27cd592f1015edf56a8c5b26276ee18a482428e7c5726
// Do not edit by hand.

enum BIP39Words {
    static let english: Set<Substring> = Set("""
    abandon ability able about above absent absorb abstract absurd abuse access accident
    account accuse achieve acid acoustic acquire across act action actor actress actual
    adapt add addict address adjust admit adult advance advice aerobic affair afford
    afraid again age agent agree ahead aim air airport aisle alarm album
    alcohol alert alien all alley allow almost alone alpha already also alter
    always amateur amazing among amount amused analyst anchor ancient anger angle angry
    animal ankle announce annual another answer antenna antique anxiety any apart apology
    appear apple approve april arch arctic area arena argue arm armed armor
    army around arrange arrest arrive arrow art artefact artist artwork ask aspect
    assault asset assist assume asthma athlete atom attack attend attitude attract auction
    audit august aunt author auto autumn average avocado avoid awake aware away
    awesome awful awkward axis baby bachelor bacon badge bag balance balcony ball
    bamboo banana banner bar barely bargain barrel base basic basket battle beach
    bean beauty because become beef before begin behave behind believe below belt
    bench benefit best betray better between beyond bicycle bid bike bind biology
    bird birth bitter black blade blame blanket blast bleak bless blind blood
    blossom blouse blue blur blush board boat body boil bomb bone bonus
    book boost border boring borrow boss bottom bounce box boy bracket brain
    brand brass brave bread breeze brick bridge brief bright bring brisk broccoli
    broken bronze broom brother brown brush bubble buddy budget buffalo build bulb
    bulk bullet bundle bunker burden burger burst bus business busy butter buyer
    buzz cabbage cabin cable cactus cage cake call calm camera camp can
    canal cancel candy cannon canoe canvas canyon capable capital captain car carbon
    card cargo carpet carry cart case cash casino castle casual cat catalog
    catch category cattle caught cause caution cave ceiling celery cement census century
    cereal certain chair chalk champion change chaos chapter charge chase chat cheap
    check cheese chef cherry chest chicken chief child chimney choice choose chronic
    chuckle chunk churn cigar cinnamon circle citizen city civil claim clap clarify
    claw clay clean clerk clever click client cliff climb clinic clip clock
    clog close cloth cloud clown club clump cluster clutch coach coast coconut
    code coffee coil coin collect color column combine come comfort comic common
    company concert conduct confirm congress connect consider control convince cook cool copper
    copy coral core corn correct cost cotton couch country couple course cousin
    cover coyote crack cradle craft cram crane crash crater crawl crazy cream
    credit creek crew cricket crime crisp critic crop cross crouch crowd crucial
    cruel cruise crumble crunch crush cry crystal cube culture cup cupboard curious
    current curtain curve cushion custom cute cycle dad damage damp dance danger
    daring dash daughter dawn day deal debate debris decade december decide decline
    decorate decrease deer defense define defy degree delay deliver demand demise denial
    dentist deny depart depend deposit depth deputy derive describe desert design desk
    despair destroy detail detect develop device devote diagram dial diamond diary dice
    diesel diet differ digital dignity dilemma dinner dinosaur direct dirt disagree discover
    disease dish dismiss disorder display distance divert divide divorce dizzy doctor document
    dog doll dolphin domain donate donkey donor door dose double dove draft
    dragon drama drastic draw dream dress drift drill drink drip drive drop
    drum dry duck dumb dune during dust dutch duty dwarf dynamic eager
    eagle early earn earth easily east easy echo ecology economy edge edit
    educate effort egg eight either elbow elder electric elegant element elephant elevator
    elite else embark embody embrace emerge emotion employ empower empty enable enact
    end endless endorse enemy energy enforce engage engine enhance enjoy enlist enough
    enrich enroll ensure enter entire entry envelope episode equal equip era erase
    erode erosion error erupt escape essay essence estate eternal ethics evidence evil
    evoke evolve exact example excess exchange excite exclude excuse execute exercise exhaust
    exhibit exile exist exit exotic expand expect expire explain expose express extend
    extra eye eyebrow fabric face faculty fade faint faith fall false fame
    family famous fan fancy fantasy farm fashion fat fatal father fatigue fault
    favorite feature february federal fee feed feel female fence festival fetch fever
    few fiber fiction field figure file film filter final find fine finger
    finish fire firm first fiscal fish fit fitness fix flag flame flash
    flat flavor flee flight flip float flock floor flower fluid flush fly
    foam focus fog foil fold follow food foot force forest forget fork
    fortune forum forward fossil foster found fox fragile frame frequent fresh friend
    fringe frog front frost frown frozen fruit fuel fun funny furnace fury
    future gadget gain galaxy gallery game gap garage garbage garden garlic garment
    gas gasp gate gather gauge gaze general genius genre gentle genuine gesture
    ghost giant gift giggle ginger giraffe girl give glad glance glare glass
    glide glimpse globe gloom glory glove glow glue goat goddess gold good
    goose gorilla gospel gossip govern gown grab grace grain grant grape grass
    gravity great green grid grief grit grocery group grow grunt guard guess
    guide guilt guitar gun gym habit hair half hammer hamster hand happy
    harbor hard harsh harvest hat have hawk hazard head health heart heavy
    hedgehog height hello helmet help hen hero hidden high hill hint hip
    hire history hobby hockey hold hole holiday hollow home honey hood hope
    horn horror horse hospital host hotel hour hover hub huge human humble
    humor hundred hungry hunt hurdle hurry hurt husband hybrid ice icon idea
    identify idle ignore ill illegal illness image imitate immense immune impact impose
    improve impulse inch include income increase index indicate indoor industry infant inflict
    inform inhale inherit initial inject injury inmate inner innocent input inquiry insane
    insect inside inspire install intact interest into invest invite involve iron island
    isolate issue item ivory jacket jaguar jar jazz jealous jeans jelly jewel
    job join joke journey joy judge juice jump jungle junior junk just
    kangaroo keen keep ketchup key kick kid kidney kind kingdom kiss kit
    kitchen kite kitten kiwi knee knife knock know lab label labor ladder
    lady lake lamp language laptop large later latin laugh laundry lava law
    lawn lawsuit layer lazy leader leaf learn leave lecture left leg legal
    legend leisure lemon lend length lens leopard lesson letter level liar liberty
    library license life lift light like limb limit link lion liquid list
    little live lizard load loan lobster local lock logic lonely long loop
    lottery loud lounge love loyal lucky luggage lumber lunar lunch luxury lyrics
    machine mad magic magnet maid mail main major make mammal man manage
    mandate mango mansion manual maple marble march margin marine market marriage mask
    mass master match material math matrix matter maximum maze meadow mean measure
    meat mechanic medal media melody melt member memory mention menu mercy merge
    merit merry mesh message metal method middle midnight milk million mimic mind
    minimum minor minute miracle mirror misery miss mistake mix mixed mixture mobile
    model modify mom moment monitor monkey monster month moon moral more morning
    mosquito mother motion motor mountain mouse move movie much muffin mule multiply
    muscle museum mushroom music must mutual myself mystery myth naive name napkin
    narrow nasty nation nature near neck need negative neglect neither nephew nerve
    nest net network neutral never news next nice night noble noise nominee
    noodle normal north nose notable note nothing notice novel now nuclear number
    nurse nut oak obey object oblige obscure observe obtain obvious occur ocean
    october odor off offer office often oil okay old olive olympic omit
    once one onion online only open opera opinion oppose option orange orbit
    orchard order ordinary organ orient original orphan ostrich other outdoor outer output
    outside oval oven over own owner oxygen oyster ozone pact paddle page
    pair palace palm panda panel panic panther paper parade parent park parrot
    party pass patch path patient patrol pattern pause pave payment peace peanut
    pear peasant pelican pen penalty pencil people pepper perfect permit person pet
    phone photo phrase physical piano picnic picture piece pig pigeon pill pilot
    pink pioneer pipe pistol pitch pizza place planet plastic plate play please
    pledge pluck plug plunge poem poet point polar pole police pond pony
    pool popular portion position possible post potato pottery poverty powder power practice
    praise predict prefer prepare present pretty prevent price pride primary print priority
    prison private prize problem process produce profit program project promote proof property
    prosper protect proud provide public pudding pull pulp pulse pumpkin punch pupil
    puppy purchase purity purpose purse push put puzzle pyramid quality quantum quarter
    question quick quit quiz quote rabbit raccoon race rack radar radio rail
    rain raise rally ramp ranch random range rapid rare rate rather raven
    raw razor ready real reason rebel rebuild recall receive recipe record recycle
    reduce reflect reform refuse region regret regular reject relax release relief rely
    remain remember remind remove render renew rent reopen repair repeat replace report
    require rescue resemble resist resource response result retire retreat return reunion reveal
    review reward rhythm rib ribbon rice rich ride ridge rifle right rigid
    ring riot ripple risk ritual rival river road roast robot robust rocket
    romance roof rookie room rose rotate rough round route royal rubber rude
    rug rule run runway rural sad saddle sadness safe sail salad salmon
    salon salt salute same sample sand satisfy satoshi sauce sausage save say
    scale scan scare scatter scene scheme school science scissors scorpion scout scrap
    screen script scrub sea search season seat second secret section security seed
    seek segment select sell seminar senior sense sentence series service session settle
    setup seven shadow shaft shallow share shed shell sheriff shield shift shine
    ship shiver shock shoe shoot shop short shoulder shove shrimp shrug shuffle
    shy sibling sick side siege sight sign silent silk silly silver similar
    simple since sing siren sister situate six size skate sketch ski skill
    skin skirt skull slab slam sleep slender slice slide slight slim slogan
    slot slow slush small smart smile smoke smooth snack snake snap sniff
    snow soap soccer social sock soda soft solar soldier solid solution solve
    someone song soon sorry sort soul sound soup source south space spare
    spatial spawn speak special speed spell spend sphere spice spider spike spin
    spirit split spoil sponsor spoon sport spot spray spread spring spy square
    squeeze squirrel stable stadium staff stage stairs stamp stand start state stay
    steak steel stem step stereo stick still sting stock stomach stone stool
    story stove strategy street strike strong struggle student stuff stumble style subject
    submit subway success such sudden suffer sugar suggest suit summer sun sunny
    sunset super supply supreme sure surface surge surprise surround survey suspect sustain
    swallow swamp swap swarm swear sweet swift swim swing switch sword symbol
    symptom syrup system table tackle tag tail talent talk tank tape target
    task taste tattoo taxi teach team tell ten tenant tennis tent term
    test text thank that theme then theory there they thing this thought
    three thrive throw thumb thunder ticket tide tiger tilt timber time tiny
    tip tired tissue title toast tobacco today toddler toe together toilet token
    tomato tomorrow tone tongue tonight tool tooth top topic topple torch tornado
    tortoise toss total tourist toward tower town toy track trade traffic tragic
    train transfer trap trash travel tray treat tree trend trial tribe trick
    trigger trim trip trophy trouble truck true truly trumpet trust truth try
    tube tuition tumble tuna tunnel turkey turn turtle twelve twenty twice twin
    twist two type typical ugly umbrella unable unaware uncle uncover under undo
    unfair unfold unhappy uniform unique unit universe unknown unlock until unusual unveil
    update upgrade uphold upon upper upset urban urge usage use used useful
    useless usual utility vacant vacuum vague valid valley valve van vanish vapor
    various vast vault vehicle velvet vendor venture venue verb verify version very
    vessel veteran viable vibrant vicious victory video view village vintage violin virtual
    virus visa visit visual vital vivid vocal voice void volcano volume vote
    voyage wage wagon wait walk wall walnut want warfare warm warrior wash
    wasp waste water wave way wealth weapon wear weasel weather web wedding
    weekend weird welcome west wet whale what wheat wheel when where whip
    whisper wide width wife wild will win window wine wing wink winner
    winter wire wisdom wise wish witness wolf woman wonder wood wool word
    work world worry worth wrap wreck wrestle wrist write wrong yard year
    yellow you young youth zebra zero zone zoo
    """.split(whereSeparator: \.isWhitespace))

    static let chineseSimplified: Set<Character> = Set("""
    的一是在不了有和人这中大为上个国我以要他时来用们生到作地于出就分对成会可主发年动同工也能下过子说产种面而方后多定行学法所民得经十
    三之进着等部度家电力里如水化高自二理起小物现实加量都两体制机当使点从业本去把性好应开它合还因由其些然前外天政四日那社义事平形相全
    表间样与关各重新线内数正心反你明看原又么利比或但质气第向道命此变条只没结解问意建月公无系军很情者最立代想已通并提直题党程展五果料
    象员革位入常文总次品式活设及管特件长求老头基资边流路级少图山统接知较将组见计别她手角期根论运农指几九区强放决西被干做必战先回则任
    取据处队南给色光门即保治北造百规热领七海口东导器压志世金增争济阶油思术极交受联什认六共权收证改清美再采转更单风切打白教速花带安场
    身车例真务具万每目至达走积示议声报斗完类八离华名确才科张信马节话米整空元况今集温传土许步群广石记需段研界拉林律叫且究观越织装影算
    低持音众书布复容儿须际商非验连断深难近矿千周委素技备半办青省列习响约支般史感劳便团往酸历市克何除消构府称太准精值号率族维划选标写
    存候毛亲快效斯院查江型眼王按格养易置派层片始却专状育厂京识适属圆包火住调满县局照参红细引听该铁价严首底液官德随病苏失尔死讲配女黄
    推显谈罪神艺呢席含企望密批营项防举球英氧势告李台落木帮轮破亚师围注远字材排供河态封另施减树溶怎止案言士均武固叶鱼波视仅费紧爱左章
    早朝害续轻服试食充兵源判护司足某练差致板田降黑犯负击范继兴似余坚曲输修故城夫够送笔船占右财吃富春职觉汉画功巴跟虽杂飞检吸助升阳互
    初创抗考投坏策古径换未跑留钢曾端责站简述钱副尽帝射草冲承独令限阿宣环双请超微让控州良轴找否纪益依优顶础载倒房突坐粉敌略客袁冷胜绝
    析块剂测丝协诉念陈仍罗盐友洋错苦夜刑移频逐靠混母短皮终聚汽村云哪既距卫停烈央察烧迅境若印洲刻括激孔搞甚室待核校散侵吧甲游久菜味旧
    模湖货损预阻毫普稳乙妈植息扩银语挥酒守拿序纸医缺雨吗针刘啊急唱误训愿审附获茶鲜粮斤孩脱硫肥善龙演父渐血欢械掌歌沙刚攻谓盾讨晚粒乱
    燃矛乎杀药宁鲁贵钟煤读班伯香介迫句丰培握兰担弦蛋沉假穿执答乐谁顺烟缩征脸喜松脚困异免背星福买染井概慢怕磁倍祖皇促静补评翻肉践尼衣
    宽扬棉希伤操垂秋宜氢套督振架亮末宪庆编牛触映雷销诗座居抓裂胞呼娘景威绿晶厚盟衡鸡孙延危胶屋乡临陆顾掉呀灯岁措束耐剧玉赵跳哥季课凯
    胡额款绍卷齐伟蒸殖永宗苗川炉岩弱零杨奏沿露杆探滑镇饭浓航怀赶库夺伊灵税途灭赛归召鼓播盘裁险康唯录菌纯借糖盖横符私努堂域枪润幅哈竟
    熟虫泽脑壤碳欧遍侧寨敢彻虑斜薄庭纳弹饲伸折麦湿暗荷瓦塞床筑恶户访塔奇透梁刀旋迹卡氯遇份毒泥退洗摆灰彩卖耗夏择忙铜献硬予繁圈雪函亦
    抽篇阵阴丁尺追堆雄迎泛爸楼避谋吨野猪旗累偏典馆索秦脂潮爷豆忽托惊塑遗愈朱替纤粗倾尚痛楚谢奋购磨君池旁碎骨监捕弟暴割贯殊释词亡壁顿
    宝午尘闻揭炮残冬桥妇警综招吴付浮遭徐您摇谷赞箱隔订男吹园纷唐败宋玻巨耕坦荣闭湾键凡驻锅救恩剥凝碱齿截炼麻纺禁废盛版缓净睛昌婚涉筒
    嘴插岸朗庄街藏姑贸腐奴啦惯乘伙恢匀纱扎辩耳彪臣亿璃抵脉秀萨俄网舞店喷纵寸汗挂洪贺闪柬爆烯津稻墙软勇像滚厘蒙芳肯坡柱荡腿仪旅尾轧冰
    贡登黎削钻勒逃障氨郭峰币港伏轨亩毕擦莫刺浪秘援株健售股岛甘泡睡童铸汤阀休汇舍牧绕炸哲磷绩朋淡尖启陷柴呈徒颜泪稍忘泵蓝拖洞授镜辛壮
    锋贫虚弯摩泰幼廷尊窗纲弄隶疑氏宫姐震瑞怪尤琴循描膜违夹腰缘珠穷森枝竹沟催绳忆邦剩幸浆栏拥牙贮礼滤钠纹罢拍咱喊袖埃勤罚焦潜伍墨欲缝
    姓刊饱仿奖铝鬼丽跨默挖链扫喝袋炭污幕诸弧励梅奶洁灾舟鉴苯讼抱毁懂寒智埔寄届跃渡挑丹艰贝碰拔爹戴码梦芽熔赤渔哭敬颗奔铅仲虎稀妹乏珍
    申桌遵允隆螺仓魏锐晓氮兼隐碍赫拨忠肃缸牵抢博巧壳兄杜讯诚碧祥柯页巡矩悲灌龄伦票寻桂铺圣恐恰郑趣抬荒腾贴柔滴猛阔辆妻填撤储签闹扰紫
    砂递戏吊陶伐喂疗瓶婆抚臂摸忍虾蜡邻胸巩挤偶弃槽劲乳邓吉仁烂砖租乌舰伴瓜浅丙暂燥橡柳迷暖牌秧胆详簧踏瓷谱呆宾糊洛辉愤竞隙怒粘乃绪肩
    籍敏涂熙皆侦悬掘享纠醒狂锁淀恨牲霸爬赏逆玩陵祝秒浙貌役彼悉鸭趋凤晨畜辈秩卵署梯炎滩棋驱筛峡冒啥寿译浸泉帽迟硅疆贷漏稿冠嫩胁芯牢叛
    蚀奥鸣岭羊凭串塘绘酵融盆锡庙筹冻辅摄袭筋拒僚旱钾鸟漆沈眉疏添棒穗硝韩逼扭侨凉挺碗栽炒杯患馏劝豪辽勃鸿旦吏拜狗埋辊掩饮搬骂辞勾扣估
    蒋绒雾丈朵姆拟宇辑陕雕偿蓄崇剪倡厅咬驶薯刷斥番赋奉佛浇漫曼扇钙桃扶仔返俗亏腔鞋棱覆框悄叔撞骗勘旺沸孤吐孟渠屈疾妙惜仰狠胀谐抛霉桑
    岗嘛衰盗渗脏赖涌甜曹阅肌哩厉烃纬毅昨伪症煮叹钉搭茎笼酷偷弓锥恒杰坑鼻翼纶叙狱逮罐络棚抑膨蔬寺骤穆冶枯册尸凸绅坯牺焰轰欣晋瘦御锭锦
    丧旬锻垄搜扑邀亭酯迈舒脆酶闲忧酚顽羽涨卸仗陪辟惩杭姚肚捉飘漂昆欺吾郎烷汁呵饰萧雅邮迁燕撒姻赴宴烦债帐斑铃旨醇董饼雏姿拌傅腹妥揉贤
    拆歪葡胺丢浩徽昂垫挡览贪慰缴汪慌冯诺姜谊凶劣诬耀昏躺盈骑乔溪丛卢抹闷咨刮驾缆悟摘铒掷颇幻柄惠惨佳仇腊窝涤剑瞧堡泼葱罩霍捞胎苍滨俩
    捅湘砍霞邵萄疯淮遂熊粪烘宿档戈驳嫂裕徙箭捐肠撑晒辨殿莲摊搅酱屏疫哀蔡堵沫皱畅叠阁莱敲辖钩痕坝巷饿祸丘玄溜曰逻彭尝卿妨艇吞韦怨矮歇
    """.filter { !$0.isWhitespace })
}
