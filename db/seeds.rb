# db/seeds.rb
# Idempotent seed data for the Shopify Dropshipping project.
# Run with: bin/rails db:seed

puts "Seeding categories..."

# =============================================================================
# CATEGORIES (FRD Section 1.3 — 13 Initial Candidates)
# =============================================================================

categories_data = [
  {
    name: "Dorm Life",
    slug: "dorm-life",
    description: "미국 대학 기숙사 생활 필수품 전문. 수납, 조명, 데스크 정리 등 사이즈 이슈 없는 CS 최소 상품 중심.",
    target_audience: "18-22세 대학생 + 학부모 (8-9월 Back-to-School 시즌 집중, 연중 신입생 유입)",
    risk_level: "low",
    example_products: ["데스크 오거나이저", "LED 클립 조명", "접이식 수납함", "미니 가습기", "도어 후크 정리대", "침대 사이드 포켓", "케이블 정리함"].to_json,
    status: "tracking",
    active: true,
    score: 9.5
  },
  {
    name: "Sleep & Rest",
    slug: "sleep-rest",
    description: "미국 수면 전문 카테고리. 미국 성인 70%가 수면 문제 경험, $432B 글로벌 수면 산업 기반 steady 수요.",
    target_audience: "25-55세 여성 중심, 수면 품질 개선에 투자 의향 높은 중산층",
    risk_level: "low",
    example_products: ["실크 아이마스크", "수면 이어플러그", "아로마 디퓨저", "가중 아이마스크", "수면 스프레이", "화이트노이즈 머신"].to_json,
    status: "tracking",
    active: true,
    score: 9.0
  },
  {
    name: "Anti-Aging Wellness",
    slug: "anti-aging-wellness",
    description: "노화 방지 웰니스 전문. 미국 Anti-aging 시장 $62B, 기구 중심으로 CS 적고 마진 높음.",
    target_audience: "35-65세 여성, 건강과 외모 관리에 적극 투자하는 층",
    risk_level: "low",
    example_products: ["구아샤 세트", "페이스 롤러(옥/로즈쿼츠)", "목/어깨 마사지 기구", "자세교정 밴드", "페이셜 스티머 악세사리"].to_json,
    status: "tracking",
    active: true,
    score: 8.5
  },
  {
    name: "Tumbler & Hydration",
    slug: "tumbler-hydration",
    description: "텀블러/수분 전문. Stanley Cup 현상 이후 텀블러 패션화. 악세사리 중심으로 사이즈/호환성 이슈 최소.",
    target_audience: "15-35세 여성 (틱톡/인스타 영향), Gen Z + 밀레니얼",
    risk_level: "low",
    example_products: ["텀블러 부츠/실리콘 바닥", "스트로 토퍼", "텀블러 스티커 팩", "텀블러 파우치/가방", "교체용 뚜껑", "세척 브러시 세트", "필터 스트로"].to_json,
    status: "tracking",
    active: true,
    score: 8.5
  },
  {
    name: "Kids Bath & Water Play",
    slug: "kids-bath-water-play",
    description: "아이 목욕/물놀이 전문. 미국 가정 일상 루틴 카테고리로 소모/교체 주기 짧고 선물 수요도 큼.",
    target_audience: "25-40세 부모 (0-8세 자녀), 선물 구매자",
    risk_level: "low",
    example_products: ["목욕 장난감 세트", "버블 메이커", "배스 크레용", "목욕 수납 네트", "미끄럼 방지 매트(아동용)", "물 온도계", "배스밤(아동용)"].to_json,
    status: "tracking",
    active: true,
    score: 8.0
  },
  {
    name: "Home Healing & Relaxation",
    slug: "home-healing-relaxation",
    description: "힐링/릴랙스 전문. 코로나 이후 at-home self-care 문화 정착. Candle 시장만 $12.6B, 감성 소비 + 반복 구매 조합.",
    target_audience: "25-55세 여성, 자기관리/셀프케어에 가치 소비하는 층",
    risk_level: "low",
    example_products: ["소이 캔들", "캔들 악세사리(위크 트리머, 스너퍼)", "아로마 오일 세트", "명상 쿠션 커버", "아이필로우", "힐링 사운드 머신"].to_json,
    status: "tracking",
    active: true,
    score: 8.0
  },
  {
    name: "Pickleball & Racquet Sports",
    slug: "pickleball-racquet-sports",
    description: "피클볼 전문. 미국 최고 성장 스포츠, 참여 인구 3,650만 명 (48% YoY 성장). 악세사리 중심으로 CS 최소화.",
    target_audience: "35-65세 남녀, 교외 거주 중산층, 커뮤니티 스포츠 참여자",
    risk_level: "medium",
    example_products: ["피클볼 그립 테이프", "교체용 볼 세트", "피클볼 가방", "손목/무릎 보호대", "스코어보드", "그립 오버랩"].to_json,
    status: "tracking",
    active: true,
    score: 7.5
  },
  {
    name: "Water Filtration & Purity",
    slug: "water-filtration-purity",
    description: "수질 필터 전문. 미국 수돗물 불신 증가, 필터 카트리지는 소모품으로 반복 구매 보장. 교체 필터/악세사리 중심.",
    target_audience: "30-55세 건강 의식 가정, 교외 주택 거주자",
    risk_level: "medium",
    example_products: ["냉장고 정수 필터(호환)", "샤워 필터", "수도꼭지 필터", "TDS 측정기", "물병 필터 교체용", "필터 피처 카트리지"].to_json,
    status: "tracking",
    active: true,
    score: 7.5
  },
  {
    name: "Travel Essentials",
    slug: "travel-essentials",
    description: "여행 용품 전문. 미국인 연간 여행 지출 $1.1T. 소형 악세사리 중심, CS 적고 impulse buy 비율 높음.",
    target_audience: "25-55세 빈번 여행자, 비즈니스 여행객 + 가족 여행",
    risk_level: "low",
    example_products: ["패킹 큐브 세트", "TSA 자물쇠", "여행용 압축 파우치", "목베개", "여권 지갑", "여행용 세면도구 병 세트", "수하물 태그"].to_json,
    status: "tracking",
    active: true,
    score: 7.0
  },
  {
    name: "Eco Kids",
    slug: "eco-kids",
    description: "친환경 아동용품 전문. 밀레니얼 부모의 환경 의식으로 수요 급증. 프리미엄 포지셔닝으로 마진 확보 가능.",
    target_audience: "28-42세 밀레니얼 부모, 환경 의식 높은 중상위 소득층",
    risk_level: "medium",
    example_products: ["대나무 아동 식기 세트", "실리콘 빨대 세트", "밀랍 랩", "유기농 면 손수건", "재사용 간식 파우치", "친환경 크레용", "나무 완구"].to_json,
    status: "tracking",
    active: true,
    score: 7.0
  },
  {
    name: "Lawn & Outdoor Maintenance",
    slug: "lawn-outdoor-maintenance",
    description: "잔디/조경 전문. 미국 주택 보유자 약 8,300만, 잔디 관리는 문화적 필수. 봄-가을 6개월 꾸준한 수요.",
    target_audience: "35-65세 교외 주택 소유자, DIY 정원 관리자",
    risk_level: "medium",
    example_products: ["스프링클러 헤드 교체", "정원 호스 노즐", "잔디 가장자리 차단막", "태양광 정원등", "화분 받침대", "잡초 방지 매트"].to_json,
    status: "tracking",
    active: true,
    score: 6.5
  },
  {
    name: "Color Theme Shop",
    slug: "color-theme-shop",
    description: "컬러 테마 전문. 특정 색상(Sage Green, Lavender)으로 통일된 라이프스타일 상품 큐레이션. TikTok/Instagram aesthetic 트렌드 부합.",
    target_audience: "18-30세 여성, SNS aesthetic 소비, 인테리어/라이프스타일 관심층",
    risk_level: "high",
    example_products: ["세이지 그린 머그컵", "라벤더 아이마스크", "컬러 매칭 캔들", "테마 수건", "컬러 파우치", "테마 노트/펜 세트", "키보드 패드"].to_json,
    status: "tracking",
    active: true,
    score: 6.5
  },
  {
    name: "Specialty Laundry & Cleaning",
    slug: "specialty-laundry-cleaning",
    description: "전용 세탁/세정 전문. 특수 용도 세정제 중심으로 니치하지만 충성 고객 확보 가능. 소모품으로 반복 구매.",
    target_audience: "25-45세 남녀, 집 관리에 관심 있는 가정",
    risk_level: "medium",
    example_products: ["운동화 세정 키트", "스테인리스 클리너", "가죽 컨디셔너", "그라우트 클리너", "세탁기 세정제", "얼룩 제거 스틱", "섬유 탈취 스프레이"].to_json,
    status: "tracking",
    active: true,
    score: 6.0
  }
]

categories_data.each do |data|
  score = data.delete(:score)
  cat = Category.find_or_initialize_by(slug: data[:slug])
  cat.assign_attributes(data)
  cat.save!
  puts "  [OK] Category: #{cat.name} (score #{score})"
end

puts "Categories seeded: #{Category.count}"

# =============================================================================
# EXCLUDED KEYWORDS (FRD Section 1.2.2)
# =============================================================================

puts "\nSeeding excluded keywords..."

excluded_keywords_data = [
  # 식품/건강보조식품
  { keyword: "food", category_pattern: "식품/건강보조식품", reason: "FDA 규제, 유통기한 관리, 반품/교환 CS 과다, 국제 배송 제한" },
  { keyword: "supplement", category_pattern: "식품/건강보조식품", reason: "FDA 규제, 유통기한 관리, 반품/교환 CS 과다, 국제 배송 제한" },
  { keyword: "vitamin", category_pattern: "식품/건강보조식품", reason: "FDA 규제, 유통기한 관리, 반품/교환 CS 과다, 국제 배송 제한" },
  { keyword: "protein", category_pattern: "식품/건강보조식품", reason: "FDA 규제, 유통기한 관리, 반품/교환 CS 과다, 국제 배송 제한" },
  { keyword: "snack", category_pattern: "식품/건강보조식품", reason: "FDA 규제, 유통기한 관리, 반품/교환 CS 과다, 국제 배송 제한" },
  { keyword: "edible", category_pattern: "식품/건강보조식품", reason: "FDA 규제, 유통기한 관리, 반품/교환 CS 과다, 국제 배송 제한" },
  { keyword: "dietary", category_pattern: "식품/건강보조식품", reason: "FDA 규제, 유통기한 관리, 반품/교환 CS 과다, 국제 배송 제한" },
  { keyword: "nutrition", category_pattern: "식품/건강보조식품", reason: "FDA 규제, 유통기한 관리, 반품/교환 CS 과다, 국제 배송 제한" },
  { keyword: "FDA approved", category_pattern: "식품/건강보조식품", reason: "FDA 규제, 유통기한 관리, 반품/교환 CS 과다, 국제 배송 제한" },
  { keyword: "organic food", category_pattern: "식품/건강보조식품", reason: "FDA 규제, 유통기한 관리, 반품/교환 CS 과다, 국제 배송 제한" },

  # 캠핑/아웃도어
  { keyword: "camping", category_pattern: "캠핑/아웃도어", reason: "대형/중량 제품 배송비 높음, 사용 후 반품 빈번, 안전 관련 CS" },
  { keyword: "tent", category_pattern: "캠핑/아웃도어", reason: "대형/중량 제품 배송비 높음, 사용 후 반품 빈번, 안전 관련 CS" },
  { keyword: "hiking", category_pattern: "캠핑/아웃도어", reason: "대형/중량 제품 배송비 높음, 사용 후 반품 빈번, 안전 관련 CS" },
  { keyword: "outdoor gear", category_pattern: "캠핑/아웃도어", reason: "대형/중량 제품 배송비 높음, 사용 후 반품 빈번, 안전 관련 CS" },
  { keyword: "backpack large", category_pattern: "캠핑/아웃도어", reason: "대형/중량 제품 배송비 높음, 사용 후 반품 빈번, 안전 관련 CS" },
  { keyword: "sleeping bag", category_pattern: "캠핑/아웃도어", reason: "대형/중량 제품 배송비 높음, 사용 후 반품 빈번, 안전 관련 CS" },
  { keyword: "campfire", category_pattern: "캠핑/아웃도어", reason: "대형/중량 제품 배송비 높음, 사용 후 반품 빈번, 안전 관련 CS" },
  { keyword: "trekking", category_pattern: "캠핑/아웃도어", reason: "대형/중량 제품 배송비 높음, 사용 후 반품 빈번, 안전 관련 CS" },

  # 공구/하드웨어
  { keyword: "tool", category_pattern: "공구/하드웨어", reason: "무게/크기 이슈, 호환성 CS, 안전사고 책임 리스크" },
  { keyword: "drill", category_pattern: "공구/하드웨어", reason: "무게/크기 이슈, 호환성 CS, 안전사고 책임 리스크" },
  { keyword: "hammer", category_pattern: "공구/하드웨어", reason: "무게/크기 이슈, 호환성 CS, 안전사고 책임 리스크" },
  { keyword: "wrench", category_pattern: "공구/하드웨어", reason: "무게/크기 이슈, 호환성 CS, 안전사고 책임 리스크" },
  { keyword: "screwdriver", category_pattern: "공구/하드웨어", reason: "무게/크기 이슈, 호환성 CS, 안전사고 책임 리스크" },
  { keyword: "power tool", category_pattern: "공구/하드웨어", reason: "무게/크기 이슈, 호환성 CS, 안전사고 책임 리스크" },
  { keyword: "saw", category_pattern: "공구/하드웨어", reason: "무게/크기 이슈, 호환성 CS, 안전사고 책임 리스크" },
  { keyword: "hardware", category_pattern: "공구/하드웨어", reason: "무게/크기 이슈, 호환성 CS, 안전사고 책임 리스크" },

  # 성인용품
  { keyword: "adult", category_pattern: "성인용품", reason: "광고 제한(Facebook/Google Ads), 반품 처리 불가, 결제 게이트웨이 제한" },
  { keyword: "sexy", category_pattern: "성인용품", reason: "광고 제한(Facebook/Google Ads), 반품 처리 불가, 결제 게이트웨이 제한" },
  { keyword: "erotic", category_pattern: "성인용품", reason: "광고 제한(Facebook/Google Ads), 반품 처리 불가, 결제 게이트웨이 제한" },
  { keyword: "intimate", category_pattern: "성인용품", reason: "광고 제한(Facebook/Google Ads), 반품 처리 불가, 결제 게이트웨이 제한" },
  { keyword: "pleasure", category_pattern: "성인용품", reason: "광고 제한(Facebook/Google Ads), 반품 처리 불가, 결제 게이트웨이 제한" },
  { keyword: "sensual", category_pattern: "성인용품", reason: "광고 제한(Facebook/Google Ads), 반품 처리 불가, 결제 게이트웨이 제한" },

  # 사이즈 의류/신발
  { keyword: "shoe size", category_pattern: "사이즈 의류/신발", reason: "사이즈 교환 CS 40%+, 반품률 업계 최고(30-40%), 재고 회전 어려움" },
  { keyword: "dress size", category_pattern: "사이즈 의류/신발", reason: "사이즈 교환 CS 40%+, 반품률 업계 최고(30-40%), 재고 회전 어려움" },
  { keyword: "clothing size", category_pattern: "사이즈 의류/신발", reason: "사이즈 교환 CS 40%+, 반품률 업계 최고(30-40%), 재고 회전 어려움" },
  { keyword: "XS", category_pattern: "사이즈 의류/신발", reason: "사이즈 교환 CS 40%+, 반품률 업계 최고(30-40%), 재고 회전 어려움" },
  { keyword: "XL", category_pattern: "사이즈 의류/신발", reason: "사이즈 교환 CS 40%+, 반품률 업계 최고(30-40%), 재고 회전 어려움" },
  { keyword: "XXL", category_pattern: "사이즈 의류/신발", reason: "사이즈 교환 CS 40%+, 반품률 업계 최고(30-40%), 재고 회전 어려움" },
  { keyword: "waist size", category_pattern: "사이즈 의류/신발", reason: "사이즈 교환 CS 40%+, 반품률 업계 최고(30-40%), 재고 회전 어려움" },
  { keyword: "men's size", category_pattern: "사이즈 의류/신발", reason: "사이즈 교환 CS 40%+, 반품률 업계 최고(30-40%), 재고 회전 어려움" },
  { keyword: "women's size", category_pattern: "사이즈 의류/신발", reason: "사이즈 교환 CS 40%+, 반품률 업계 최고(30-40%), 재고 회전 어려움" },

  # 전자기기 본체
  { keyword: "laptop", category_pattern: "전자기기 본체", reason: "고장/불량 CS, 보증 이슈, 높은 반품률, A/S 대응 불가" },
  { keyword: "phone", category_pattern: "전자기기 본체", reason: "고장/불량 CS, 보증 이슈, 높은 반품률, A/S 대응 불가" },
  { keyword: "tablet", category_pattern: "전자기기 본체", reason: "고장/불량 CS, 보증 이슈, 높은 반품률, A/S 대응 불가" },
  { keyword: "computer", category_pattern: "전자기기 본체", reason: "고장/불량 CS, 보증 이슈, 높은 반품률, A/S 대응 불가" },
  { keyword: "TV", category_pattern: "전자기기 본체", reason: "고장/불량 CS, 보증 이슈, 높은 반품률, A/S 대응 불가" },
  { keyword: "monitor", category_pattern: "전자기기 본체", reason: "고장/불량 CS, 보증 이슈, 높은 반품률, A/S 대응 불가" },
  { keyword: "console", category_pattern: "전자기기 본체", reason: "고장/불량 CS, 보증 이슈, 높은 반품률, A/S 대응 불가" },
  { keyword: "gaming system", category_pattern: "전자기기 본체", reason: "고장/불량 CS, 보증 이슈, 높은 반품률, A/S 대응 불가" },

  # 유리/세라믹
  { keyword: "glass", category_pattern: "유리/세라믹", reason: "배송 중 파손 CS, 교체 배송 비용, 패키징 비용 상승" },
  { keyword: "ceramic", category_pattern: "유리/세라믹", reason: "배송 중 파손 CS, 교체 배송 비용, 패키징 비용 상승" },
  { keyword: "porcelain", category_pattern: "유리/세라믹", reason: "배송 중 파손 CS, 교체 배송 비용, 패키징 비용 상승" },
  { keyword: "crystal", category_pattern: "유리/세라믹", reason: "배송 중 파손 CS, 교체 배송 비용, 패키징 비용 상승" },
  { keyword: "fragile glassware", category_pattern: "유리/세라믹", reason: "배송 중 파손 CS, 교체 배송 비용, 패키징 비용 상승" },

  # 가구/대형
  { keyword: "furniture", category_pattern: "가구/대형", reason: "배송비 마진 잠식, 조립 CS, 파손 교환 비용 과다" },
  { keyword: "sofa", category_pattern: "가구/대형", reason: "배송비 마진 잠식, 조립 CS, 파손 교환 비용 과다" },
  { keyword: "desk", category_pattern: "가구/대형", reason: "배송비 마진 잠식, 조립 CS, 파손 교환 비용 과다" },
  { keyword: "table", category_pattern: "가구/대형", reason: "배송비 마진 잠식, 조립 CS, 파손 교환 비용 과다" },
  { keyword: "bed frame", category_pattern: "가구/대형", reason: "배송비 마진 잠식, 조립 CS, 파손 교환 비용 과다" },
  { keyword: "bookshelf", category_pattern: "가구/대형", reason: "배송비 마진 잠식, 조립 CS, 파손 교환 비용 과다" },
  { keyword: "cabinet", category_pattern: "가구/대형", reason: "배송비 마진 잠식, 조립 CS, 파손 교환 비용 과다" },
  { keyword: "wardrobe", category_pattern: "가구/대형", reason: "배송비 마진 잠식, 조립 CS, 파손 교환 비용 과다" },

  # 의약품/의료기기
  { keyword: "prescription", category_pattern: "의약품/의료기기", reason: "FDA 승인 필수, 법적 책임, 클레임 리스크 극대" },
  { keyword: "medicine", category_pattern: "의약품/의료기기", reason: "FDA 승인 필수, 법적 책임, 클레임 리스크 극대" },
  { keyword: "medical device", category_pattern: "의약품/의료기기", reason: "FDA 승인 필수, 법적 책임, 클레임 리스크 극대" },
  { keyword: "pharmaceutical", category_pattern: "의약품/의료기기", reason: "FDA 승인 필수, 법적 책임, 클레임 리스크 극대" },
  { keyword: "drug", category_pattern: "의약품/의료기기", reason: "FDA 승인 필수, 법적 책임, 클레임 리스크 극대" },
  { keyword: "FDA regulated", category_pattern: "의약품/의료기기", reason: "FDA 승인 필수, 법적 책임, 클레임 리스크 극대" },

  # 라이선스 캐릭터
  { keyword: "Disney", category_pattern: "라이선스 캐릭터", reason: "저작권/상표권 침해 리스크, Amazon 브랜드 게이팅" },
  { keyword: "Marvel", category_pattern: "라이선스 캐릭터", reason: "저작권/상표권 침해 리스크, Amazon 브랜드 게이팅" },
  { keyword: "Nintendo", category_pattern: "라이선스 캐릭터", reason: "저작권/상표권 침해 리스크, Amazon 브랜드 게이팅" },
  { keyword: "Pokemon", category_pattern: "라이선스 캐릭터", reason: "저작권/상표권 침해 리스크, Amazon 브랜드 게이팅" },
  { keyword: "Hello Kitty", category_pattern: "라이선스 캐릭터", reason: "저작권/상표권 침해 리스크, Amazon 브랜드 게이팅" },
  { keyword: "licensed", category_pattern: "라이선스 캐릭터", reason: "저작권/상표권 침해 리스크, Amazon 브랜드 게이팅" },
  { keyword: "trademark", category_pattern: "라이선스 캐릭터", reason: "저작권/상표권 침해 리스크, Amazon 브랜드 게이팅" }
]

excluded_keywords_data.each do |data|
  kw = ExcludedKeyword.find_or_initialize_by(keyword: data[:keyword], category_pattern: data[:category_pattern])
  kw.assign_attributes(data)
  kw.save!
end

puts "Excluded keywords seeded: #{ExcludedKeyword.count}"

# =============================================================================
# MOCK SNAPSHOT DATA (3 days, top 3 categories for dashboard testing)
# =============================================================================

puts "\nSeeding mock category snapshots..."

dorm_life    = Category.find_by!(slug: "dorm-life")
sleep_rest   = Category.find_by!(slug: "sleep-rest")
anti_aging   = Category.find_by!(slug: "anti-aging-wellness")

today = Date.today

snapshots_data = [
  # --- Dorm Life ---
  {
    category: dorm_life,
    snapshot_date: today - 2,
    avg_bsr: 38500,
    bsr_7d_change: -9.2,
    bsr_30d_change: -21.5,
    new_entries: 31,
    total_products: 8200,
    avg_price: 34.50,
    price_in_range_pct: 88.5,
    avg_reviews: 1240,
    avg_rating: 4.4,
    fba_ratio: 0.55,
    trends_interest: 68,
    trends_cv: 0.18,
    trends_yoy: "+22%",
    reddit_mentions: 210,
    reddit_sentiment: 0.78,
    tiktok_views: "4.1M",
    movers_data: { top_products: ["LED Clip Light", "Bed Side Caddy", "Desk Organizer"], category_spike: true }.to_json,
    competitor_data: { stores_count: 32, avg_product_count: 95, top_traffic: "62K" }.to_json,
    raw_data: { source: "mock", generated_at: (today - 2).to_s }.to_json
  },
  {
    category: dorm_life,
    snapshot_date: today - 1,
    avg_bsr: 36800,
    bsr_7d_change: -10.1,
    bsr_30d_change: -22.8,
    new_entries: 34,
    total_products: 8250,
    avg_price: 34.20,
    price_in_range_pct: 89.0,
    avg_reviews: 1265,
    avg_rating: 4.4,
    fba_ratio: 0.56,
    trends_interest: 71,
    trends_cv: 0.17,
    trends_yoy: "+23%",
    reddit_mentions: 225,
    reddit_sentiment: 0.80,
    tiktok_views: "4.4M",
    movers_data: { top_products: ["Mini Humidifier", "Cable Organizer", "Door Hook Rack"], category_spike: true }.to_json,
    competitor_data: { stores_count: 33, avg_product_count: 97, top_traffic: "64K" }.to_json,
    raw_data: { source: "mock", generated_at: (today - 1).to_s }.to_json
  },
  {
    category: dorm_life,
    snapshot_date: today,
    avg_bsr: 35200,
    bsr_7d_change: -11.3,
    bsr_30d_change: -24.1,
    new_entries: 37,
    total_products: 8310,
    avg_price: 33.90,
    price_in_range_pct: 89.5,
    avg_reviews: 1290,
    avg_rating: 4.5,
    fba_ratio: 0.57,
    trends_interest: 74,
    trends_cv: 0.16,
    trends_yoy: "+25%",
    reddit_mentions: 240,
    reddit_sentiment: 0.82,
    tiktok_views: "4.8M",
    movers_data: { top_products: ["Foldable Storage Bin", "Clip Light Pro", "Side Pocket"], category_spike: true }.to_json,
    competitor_data: { stores_count: 35, avg_product_count: 100, top_traffic: "67K" }.to_json,
    raw_data: { source: "mock", generated_at: today.to_s }.to_json
  },

  # --- Sleep & Rest ---
  {
    category: sleep_rest,
    snapshot_date: today - 2,
    avg_bsr: 46100,
    bsr_7d_change: -11.8,
    bsr_30d_change: -17.2,
    new_entries: 21,
    total_products: 12400,
    avg_price: 42.80,
    price_in_range_pct: 84.0,
    avg_reviews: 2780,
    avg_rating: 4.3,
    fba_ratio: 0.59,
    trends_interest: 70,
    trends_cv: 0.09,
    trends_yoy: "+7%",
    reddit_mentions: 320,
    reddit_sentiment: 0.81,
    tiktok_views: "2.1M",
    movers_data: { top_products: ["Silk Eye Mask", "White Noise Machine", "Sleep Spray"], category_spike: false }.to_json,
    competitor_data: { stores_count: 43, avg_product_count: 115, top_traffic: "82K" }.to_json,
    raw_data: { source: "mock", generated_at: (today - 2).to_s }.to_json
  },
  {
    category: sleep_rest,
    snapshot_date: today - 1,
    avg_bsr: 45500,
    bsr_7d_change: -12.1,
    bsr_30d_change: -17.9,
    new_entries: 22,
    total_products: 12450,
    avg_price: 42.60,
    price_in_range_pct: 84.5,
    avg_reviews: 2810,
    avg_rating: 4.3,
    fba_ratio: 0.60,
    trends_interest: 71,
    trends_cv: 0.09,
    trends_yoy: "+8%",
    reddit_mentions: 330,
    reddit_sentiment: 0.82,
    tiktok_views: "2.2M",
    movers_data: { top_products: ["Weighted Eye Mask", "Sunrise Alarm", "Silk Pillowcase"], category_spike: false }.to_json,
    competitor_data: { stores_count: 44, avg_product_count: 118, top_traffic: "84K" }.to_json,
    raw_data: { source: "mock", generated_at: (today - 1).to_s }.to_json
  },
  {
    category: sleep_rest,
    snapshot_date: today,
    avg_bsr: 45230,
    bsr_7d_change: -12.5,
    bsr_30d_change: -18.3,
    new_entries: 23,
    total_products: 12500,
    avg_price: 42.50,
    price_in_range_pct: 85.0,
    avg_reviews: 2847,
    avg_rating: 4.3,
    fba_ratio: 0.60,
    trends_interest: 72,
    trends_cv: 0.08,
    trends_yoy: "+8%",
    reddit_mentions: 340,
    reddit_sentiment: 0.82,
    tiktok_views: "2.3M",
    movers_data: { top_products: ["Weighted Eye Mask", "Sleep Spray", "White Noise Speaker"], category_spike: false }.to_json,
    competitor_data: { stores_count: 45, avg_product_count: 120, top_traffic: "85K" }.to_json,
    raw_data: { source: "mock", generated_at: today.to_s }.to_json
  },

  # --- Anti-Aging Wellness ---
  {
    category: anti_aging,
    snapshot_date: today - 2,
    avg_bsr: 52100,
    bsr_7d_change: -7.8,
    bsr_30d_change: -13.4,
    new_entries: 17,
    total_products: 9800,
    avg_price: 48.20,
    price_in_range_pct: 79.0,
    avg_reviews: 1890,
    avg_rating: 4.2,
    fba_ratio: 0.52,
    trends_interest: 64,
    trends_cv: 0.11,
    trends_yoy: "+12%",
    reddit_mentions: 185,
    reddit_sentiment: 0.76,
    tiktok_views: "3.2M",
    movers_data: { top_products: ["Gua Sha Set", "Rose Quartz Roller", "Posture Band"], category_spike: false }.to_json,
    competitor_data: { stores_count: 38, avg_product_count: 88, top_traffic: "55K" }.to_json,
    raw_data: { source: "mock", generated_at: (today - 2).to_s }.to_json
  },
  {
    category: anti_aging,
    snapshot_date: today - 1,
    avg_bsr: 51400,
    bsr_7d_change: -8.2,
    bsr_30d_change: -14.0,
    new_entries: 18,
    total_products: 9840,
    avg_price: 48.00,
    price_in_range_pct: 79.5,
    avg_reviews: 1920,
    avg_rating: 4.2,
    fba_ratio: 0.53,
    trends_interest: 65,
    trends_cv: 0.11,
    trends_yoy: "+13%",
    reddit_mentions: 192,
    reddit_sentiment: 0.77,
    tiktok_views: "3.4M",
    movers_data: { top_products: ["Face Roller Jade", "Shoulder Massager", "Facial Steamer"], category_spike: false }.to_json,
    competitor_data: { stores_count: 39, avg_product_count: 90, top_traffic: "57K" }.to_json,
    raw_data: { source: "mock", generated_at: (today - 1).to_s }.to_json
  },
  {
    category: anti_aging,
    snapshot_date: today,
    avg_bsr: 50800,
    bsr_7d_change: -8.6,
    bsr_30d_change: -14.7,
    new_entries: 19,
    total_products: 9880,
    avg_price: 47.80,
    price_in_range_pct: 80.0,
    avg_reviews: 1950,
    avg_rating: 4.3,
    fba_ratio: 0.53,
    trends_interest: 66,
    trends_cv: 0.10,
    trends_yoy: "+13%",
    reddit_mentions: 198,
    reddit_sentiment: 0.78,
    tiktok_views: "3.6M",
    movers_data: { top_products: ["Gua Sha Stone", "Eye Roller", "Neck Stretcher"], category_spike: false }.to_json,
    competitor_data: { stores_count: 40, avg_product_count: 92, top_traffic: "59K" }.to_json,
    raw_data: { source: "mock", generated_at: today.to_s }.to_json
  }
]

snapshots_data.each do |data|
  category = data.delete(:category)
  snap = CategorySnapshot.find_or_initialize_by(
    category_id: category.id,
    snapshot_date: data[:snapshot_date]
  )
  snap.assign_attributes(data)
  snap.save!
end

puts "Category snapshots seeded: #{CategorySnapshot.count}"

# =============================================================================
# MOCK RECOMMENDATIONS (3 recommendations for UI testing)
# =============================================================================

puts "\nSeeding mock recommendations..."

recommendations_data = [
  {
    category: sleep_rest,
    score: 9.0,
    score_breakdown: {
      demand_stability: {
        score: 9.2,
        reason: "Google Trends 변동계수 0.08은 추적 중인 전체 카테고리 중 상위 5% 안정성. 12개월 평균 72로 검색 기반이 탄탄하며, YoY +8% 완만한 성장은 버블이 아닌 구조적 수요 증가를 시사"
      },
      growth_momentum: {
        score: 8.5,
        reason: "30일 BSR -18.3%는 판매 가속을 의미. 신규 진입 23개/월은 공급자도 기회를 인지하고 있으나, 아직 포화 단계가 아님"
      },
      competition_landscape: {
        score: 8.0,
        reason: "FBA 비율 60%는 대형 셀러 장악이 아직 심하지 않음을 의미. Shopify 유사 스토어 45개는 경쟁 있지만 Category Killer 포지셔닝으로 차별화 가능"
      },
      margin_potential: {
        score: 9.0,
        reason: "평균 소싱가 기준 $30-80 범위 적합 상품 85%. 수면 용품은 건강 프레임으로 가격 프리미엄 가능"
      },
      cs_risk: {
        score: 9.5,
        reason: "사이즈 없음, 전자 부품 최소, 소모/소형품 위주. 드롭쉬핑 CS 리스크 최하위 그룹"
      },
      category_killer_fit: {
        score: 8.8,
        reason: "'수면 전문 스토어' 컨셉은 미국 소비자에게 직관적. 크로스셀 구조 자연스러움 (아이마스크→디퓨저→화이트노이즈)"
      }
    }.to_json,
    insight: "Google Trends 12개월 변동계수 0.08로 시즌 영향 없는 steady 수요. 미국 성인 70%가 수면 문제를 경험하는 구조적 시장으로, 일시적 트렌드가 아닌 항상적 수요가 존재한다. 평균 소싱가 $28 대비 Shopify 판매가 $42 설정 시 33% 마진 확보 가능하며, 실크 아이마스크→아로마 디퓨저→화이트노이즈 머신으로 이어지는 자연스러운 크로스셀 구조로 객단가 상승이 용이하다. 2022년 텀블러 카테고리와 유사한 초기 안정 성장 패턴을 보이고 있어 조기 진입 시 Category Killer 포지셔닝 선점 가능.",
    risks: ["LED 마스크 등 전자기기 포함 시 CS 급증 가능 → 비전자 아이템만 취급 권장", "아로마/스프레이류는 항공 배송 제한 가능 → 배송 방식 사전 확인 필요", "수면 산업 경쟁 심화 시 차별화 컨셉 필수 → 'Science-backed Sleep' 브랜딩 권장"].to_json,
    action_items: ["1단계: 비전자 수면 악세사리 50개로 시작 (실크 아이마스크, 귀마개, 아로마 시리즈)", "2단계: 'Sleep Better Shop' 브랜딩으로 Category Killer 포지셔닝", "3단계: Sleep Foundation 등 백링크 확보로 SEO 기반 구축", "4단계: 주간 수면 팁 콘텐츠로 이메일 리스트 빌딩"].to_json,
    similar_pattern: "2022 Q3의 텀블러 카테고리와 유사한 초기 안정 성장 패턴. 당시 텀블러는 발견 점수 7.5에서 3분기 후 시장 규모 $4.2B로 explosive_growth.",
    status: "pending",
    model_version: "claude-opus-4-6",
    week_number: Date.today.cweek
  },
  {
    category: dorm_life,
    score: 9.5,
    score_breakdown: {
      demand_stability: {
        score: 8.5,
        reason: "Back-to-School 시즌(8-9월) 집중 수요이나, 전국 365일 신입생 유입으로 연중 기저 수요 유지. 변동계수 0.16으로 시즌성 있으나 허용 범위 내"
      },
      growth_momentum: {
        score: 9.8,
        reason: "미국 대학생 약 2,000만 명, 매년 코호트 갱신. BSR 30일 변화 -24.1%로 가파른 상승세. TikTok '기숙사 꾸미기' 콘텐츠 4.8M 뷰로 소셜 트리거 강함"
      },
      competition_landscape: {
        score: 9.0,
        reason: "Shopify 전문 스토어 35개로 상대적으로 미개척. FBA 비율 57%로 대형 셀러 장악 중간 단계, 니치 전문화로 차별화 여지 충분"
      },
      margin_potential: {
        score: 9.5,
        reason: "기숙사 용품은 학부모 구매 비율 높아 가격 민감도 낮음. 평균 $33.90, $30-80 범위 적합률 89.5%. 번들 판매(데스크 세트, 룸 스타터킷) 전략으로 객단가 $60+ 가능"
      },
      cs_risk: {
        score: 9.8,
        reason: "사이즈/호환성 이슈 거의 없음. LED 조명, 수납함, 훅 등 단순 구조 상품. 반품률 추정 5% 미만으로 드롭쉬핑 최적 카테고리"
      },
      category_killer_fit: {
        score: 9.5,
        reason: "'Dorm Life 전문 스토어' 컨셉 미국 대학생에게 즉각 인식. 학교별 컬렉션, 전공별 큐레이션 등 콘텐츠 마케팅 확장성 최고"
      }
    }.to_json,
    insight: "미국 대학생 2,000만 명이라는 명확한 타겟 코호트가 매년 갱신되는 구조적 수요. Back-to-School 피크(8-9월) 외에도 봄 학기 신입생, 편입생, 기숙사 이동 수요로 연중 매출 창출 가능. 학부모 구매 비율이 높아 가격 민감도가 낮고, 번들 상품(기숙사 스타터킷 $59.99)으로 객단가 극대화 전략이 유효하다. BSR 30일 -24.1% 상승으로 현재 모멘텀이 가장 강한 카테고리.",
    risks: ["8-9월 피크 집중으로 연간 매출 편중 가능 → 봄 학기/이사 시즌 프로모션으로 분산", "대형 이커머스(Target, Amazon) 동일 상품 경쟁 → 전문 스토어 브랜딩과 큐레이션으로 차별화 필수"].to_json,
    action_items: ["1단계: 기숙사 필수품 탑 30개 선별 (수납, 조명, 데스크 정리 중심)", "2단계: '기숙사 스타터킷' 번들 상품 기획 ($49.99-$79.99)", "3단계: 학교/전공 서브레딧 타겟 Reddit 마케팅", "4단계: Back-to-School 7월 초 론칭으로 피크 시즌 선점"].to_json,
    similar_pattern: "2019년 WFH(재택근무) 홈오피스 용품 카테고리와 유사. 명확한 타겟 + 시즌 피크 + 번들 전략으로 첫 해 $200K+ 매출 달성 사례.",
    status: "pending",
    model_version: "claude-opus-4-6",
    week_number: Date.today.cweek
  },
  {
    category: anti_aging,
    score: 8.5,
    score_breakdown: {
      demand_stability: {
        score: 8.0,
        reason: "Anti-aging 수요는 나이와 함께 증가하는 구조적 시장. Google Trends 변동계수 0.10으로 비교적 안정적. 베이비부머 고령화로 장기 성장 보장"
      },
      growth_momentum: {
        score: 8.5,
        reason: "YoY +13% 성장, TikTok에서 #antiaging 관련 콘텐츠 3.6M 뷰. 40대 이상 여성의 소셜 미디어 유입 증가로 온라인 구매 전환율 상승 중"
      },
      competition_landscape: {
        score: 7.5,
        reason: "Shopify 스토어 40개로 경쟁 있음. 그러나 비전자 기구(구아샤, 롤러) 전문화로 차별화 가능. 대형 뷰티 브랜드와 가격 경쟁 대신 'Holistic Wellness' 포지셔닝"
      },
      margin_potential: {
        score: 9.0,
        reason: "40-60대 여성 구매력 최상위. 평균 판매가 $47.80, 건강/뷰티 프레임으로 프리미엄 가격 수용도 높음. 구아샤+롤러+스티머 세트 번들 $69.99 전략 유효"
      },
      cs_risk: {
        score: 8.5,
        reason: "비전자 기구 위주로 고장/불량 CS 최소. 사이즈 이슈 없음. 단, 효과 기대치 불일치로 인한 환불 요청 일부 발생 가능 → 현실적 상품 설명 필수"
      },
      category_killer_fit: {
        score: 8.0,
        reason: "'Anti-Aging 전문 스토어' 컨셉 명확. 구아샤→페이스 롤러→마사지 기구 크로스셀 자연스러움. YouTube/Instagram 뷰티 인플루언서 협업 콘텐츠 마케팅 용이"
      }
    }.to_json,
    insight: "미국 Anti-aging 시장 $62B 중 비전자 기구(구아샤, 롤러, 마사지 도구) 세그먼트는 드롭쉬핑 최적 구간. FDA 규제 대상이 아닌 기구 중심으로 취급하면 법적 리스크 없이 고마진 확보 가능. 40-60대 여성은 구매력이 가장 높은 연령대이며, 소셜 미디어 뷰티 콘텐츠 소비 증가로 온라인 구매 전환이 활발하다. Holistic Wellness 트렌드와 결합한 전문 스토어 포지셔닝이 유효.",
    risks: ["효과 미흡으로 인한 환불 요청 가능 → 리뷰 기반 상품 선별 필수 (평점 4.3+ 이상)", "FDA 규제 경계선 제품(EMS, LED 마스크) 혼입 시 법적 리스크 → 순수 기구/악세사리만 취급", "과장 광고 표현 주의 → FTC 건강 클레임 가이드라인 준수 필수"].to_json,
    action_items: ["1단계: 비전자 기구 40개 선별 (구아샤, 롤러, 마사지볼, 자세교정 밴드)", "2단계: 'Glow & Age Gracefully' 브랜드 스토리 수립", "3단계: Instagram/Pinterest 비주얼 마케팅 채널 개설", "4단계: YouTube 뷰티 인플루언서 5명과 제품 협찬 콜라보"].to_json,
    similar_pattern: "2020년 홈 피트니스 기구 카테고리와 유사. 팬데믹 계기로 비전자 피트니스 악세사리(요가매트, 저항밴드) 시장이 2년간 3배 성장한 패턴과 유사한 구조적 성장세.",
    status: "pending",
    model_version: "claude-opus-4-6",
    week_number: Date.today.cweek
  }
]

recommendations_data.each do |data|
  category = data.delete(:category)
  # Use find_or_create_by on category + week_number to allow re-seeding
  rec = Recommendation.find_or_initialize_by(
    category_id: category.id,
    week_number: data[:week_number]
  )
  rec.assign_attributes(data)
  rec.save!
  puts "  [OK] Recommendation: #{category.name} (score #{rec.score})"
end

puts "Recommendations seeded: #{Recommendation.count}"

# =============================================================================
# COMPETITOR STORES (5 mock Shopify stores)
# =============================================================================

puts "\nSeeding competitor stores..."

competitor_stores_data = [
  {
    name: "DormEssentials Co.",
    url: "https://dormessentials.myshopify.com",
    shopify_domain: "dormessentials.myshopify.com",
    active: true
  },
  {
    name: "SleepWell Shop",
    url: "https://sleepwellshop.myshopify.com",
    shopify_domain: "sleepwellshop.myshopify.com",
    active: true
  },
  {
    name: "AgeGraceful Wellness",
    url: "https://agegraceful.myshopify.com",
    shopify_domain: "agegraceful.myshopify.com",
    active: true
  },
  {
    name: "HydratePro Store",
    url: "https://hydratepro.myshopify.com",
    shopify_domain: "hydratepro.myshopify.com",
    active: true
  },
  {
    name: "HomeHeal Marketplace",
    url: "https://homeheal.myshopify.com",
    shopify_domain: "homeheal.myshopify.com",
    active: true
  }
]

competitor_stores_data.each do |data|
  store = CompetitorStore.find_or_initialize_by(shopify_domain: data[:shopify_domain])
  store.assign_attributes(data)
  store.save!
  puts "  [OK] Competitor: #{store.name}"
end

puts "Competitor stores seeded: #{CompetitorStore.count}"

puts "\nSeed complete!"
puts "  Categories:          #{Category.count}"
puts "  Excluded Keywords:   #{ExcludedKeyword.count}"
puts "  Category Snapshots:  #{CategorySnapshot.count}"
puts "  Recommendations:     #{Recommendation.count}"
puts "  Competitor Stores:   #{CompetitorStore.count}"
