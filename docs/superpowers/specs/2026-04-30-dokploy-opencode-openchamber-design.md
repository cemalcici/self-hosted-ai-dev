# Dokploy üzerinde OpenCode + oh-my-opencode-slim + OpenChamber Stack Tasarımı

## Özet

Bu tasarımın amacı, Dokploy üzerinde tek bir `docker-compose.yml` ile ayağa kaldırılabilen, OpenChamber web arayüzünü OpenCode backend'ine bağlayan ve `oh-my-opencode-slim` eklentisini OpenCode image'ı içine önceden kuran bir stack tanımlamaktır.

Hedef kullanım modeli web odaklıdır: kullanıcı Cloudflare DNS üzerinden Dokploy tarafından yayınlanan OpenChamber arayüzüne erişir, GitHub hesabını OpenChamber UI üzerinden bağlar, repository klonlar ve aynı paylaşılan workspace volume üzerinden OpenCode'un bu repository'lerde agent akışları çalıştırmasını sağlar.

## Hedefler

- Tek bir `docker-compose.yml` ile stack'in tanımlanması
- `opencode` servisinin custom Dockerfile ile build edilmesi
- `oh-my-opencode-slim` paketinin `opencode` image'ına preinstalled olarak eklenmesi
- `openchamber` servisinin ayrı bir web/UI katmanı olarak çalışması
- OpenChamber ile OpenCode arasında servis adı üzerinden iç ağ iletişimi kurulması
- GitHub entegrasyonunun OpenChamber UI üzerinden yapılabilmesi
- OpenChamber ve OpenCode'un aynı workspace volume'ünü paylaşması
- Ortam değişkenlerinin repo içindeki `.env.example` şablonuyla belgelenmesi
- Çözümün Dokploy dağıtım modeline uygun kalması

## Hedef Dışı Olanlar

- Tek container içinde çoklu proses çalıştıran birleşik image tasarımı
- SSH mount ile Git erişimi
- Container içine kalıcı GitHub PAT, `.git-credentials` veya kullanıcıya özel SSH anahtarı bake etmek
- Çok kullanıcılı tenant izolasyonu
- Merkezi SSO, harici secret manager veya otomatik GitHub→Dokploy deployment orkestrasyonu

## Araştırma Bulguları

### OpenCode

- OpenCode için resmi Docker image kullanımı belgelenmiş durumda.
- Bun tabanlı kurulumda çalışır CLI paketi `opencode-ai` olarak dağıtılıyor; çalıştırılan binary adı ise `opencode`.
- Headless servis modeli `opencode serve --hostname 0.0.0.0 --port 4096` ile destekleniyor.
- Sunucu erişimi için `OPENCODE_SERVER_PASSWORD` ve isteğe bağlı `OPENCODE_SERVER_USERNAME` gibi environment variable'lar mevcut.
- Veri ve config dizinleri XDG tabanlı dizinlerle yönlendirilebiliyor.

### oh-my-opencode-slim

- Paket OpenCode eklentisi olarak çalışıyor.
- Kurulum akışı OpenCode config'ine plugin tanımı eklemeyi ve gerektiğinde lite config üretmeyi içeriyor.
- `bunx oh-my-opencode-slim@latest install --no-tui --skills=yes` gibi non-interactive kurulum modelleri belgelenmiş durumda.
- OpenCode port bilgisiyle birlikte çalışabilen bir yapı sunuyor.

### OpenChamber

- OpenChamber, harici bir OpenCode backend'ine `OPENCODE_HOST` veya `OPENCODE_PORT` ile bağlanabiliyor.
- `OPENCODE_SKIP_START=true` kullanıldığında kendi gömülü OpenCode başlatması devre dışı bırakılabiliyor.
- Upstream Docker/compose dağıtım örnekleri prebuilt registry image yerine source tree içinden local build yaklaşımı kullanıyor.
- GitHub authentication için UI/server tarafında device flow destekleyen yerleşik modüller var.
- Repository clone yardımcıları ve GitHub odaklı workflow yetenekleri bulunuyor.

### Dokploy

- Docker Compose stack'leri Dokploy üzerinde domain ile yayınlanabiliyor.
- Domain ve Traefik routing tarafını Dokploy yöneteceği için compose dosyasının bu sorumluluğu taşıması gerekmiyor.
- Kullanıcı, environment variable'ları Dokploy arayüzünden yönetebiliyor.
- Volume lifecycle yönetimi Dokploy tarafında çözülebildiği için compose içinde servislerin paylaştığı volume yapısına odaklanmak yeterli.

## Mimari Kararlar

### Karar 1: İki servisli yapı kullanılacak

Stack iki ana servisten oluşacak:

1. `opencode`
2. `openchamber`

`oh-my-opencode-slim` ayrı servis olmayacak; `opencode` image'ının içinde yer alacak.

Bu seçimle UI katmanı ile backend/agent katmanı ayrılır. Sorun ayıklama, güncelleme ve bakım daha sade hale gelir.

### Karar 2: `opencode` custom Dockerfile ile build edilecek

`opencode` servisi için özel bir Dockerfile yazılacak. Bu image:

- OpenCode'u kuracak
- pratikte bunu `bun add -g opencode-ai` ile yapacak ve container içinde `opencode` binary'sini sağlayacak
- `oh-my-opencode-slim` paketini kuracak
- runtime'da gereken bootstrap akışı için gerekli script veya entrypoint katmanını taşıyacak

Kullanıcıya özel secret, GitHub auth veya runtime state build aşamasına gömülmeyecek.

### Karar 3: `openchamber` ayrı servis olacak

OpenChamber, web arayüzü ve GitHub entegrasyon katmanı olarak ayrı serviste tutulacak. Bu servis:

- repo içine `openchamber/` git submodule olarak eklenecek upstream source tree'den build edilecek
- release tag'e pinlenecek; ilk hedef ref `v1.9.10` olacak
- kendi embedded OpenCode örneğini başlatmayacak
- `OPENCODE_HOST=http://opencode:4096` ile backend'e bağlanacak
- `OPENCODE_SKIP_START=true` ile iç sunucu başlatmayı kapatacak

Bu kararın nedeni, `ghcr.io/openchamber/openchamber:main` image referansının çekilememesi ve upstream'in resmi compose örneklerinde de local build modelinin kullanılmasıdır.

### Karar 4: Ortak workspace volume kullanılacak

OpenChamber ve OpenCode aynı workspace volume'ünü mount edecek.

Bu sayede:

- OpenChamber UI üzerinden klonlanan repository'ler ortak çalışma alanına yazılır
- OpenCode backend aynı repository'ler üzerinde doğrudan çalışır
- Ek senkronizasyon veya kopyalama katmanı gerekmez

### Karar 5: GitHub entegrasyonu sadece OpenChamber UI üzerinden yapılacak

GitHub bağlantısı için SSH mount veya klasik container içi git credential modeli tasarlanmayacak. Kullanıcı GitHub hesabını OpenChamber arayüzünden bağlayacak.

Bu yaklaşımın nedenleri:

- Dokploy üzerinde web odaklı kullanım modeline daha uygun olması
- Secret yüzeyini küçültmesi
- kullanıcı deneyimini sadeleştirmesi
- OpenChamber'in yerleşik GitHub auth özelliklerini değerlendirmesi

### Karar 6: Environment yönetimi `.env.example` ile belgelenmiş olacak

Repo içinde gerçek `.env` tutulmayacak. Bunun yerine bir `.env.example` dosyası bulunacak.

Bu dosya:

- gerekli environment variable adlarını gösterecek
- örnek/placeholder değerler içerecek
- hangi değişkenin zorunlu, hangisinin opsiyonel olduğunu yorumlarla belirtecek
- Dokploy arayüzünde doldurulacak değerler için rehber olacak

## Servis Sorumlulukları

### `opencode`

Sorumluluklar:

- OpenCode backend'i çalıştırmak
- `oh-my-opencode-slim` eklentisini hazır halde sunmak
- paylaşılan workspace üzerinde agent iş akışlarını yürütmek
- kendi config ve state verisini kalıcı volume'lerde tutmak

Beklenen başlangıç komutu:

- `opencode serve --hostname 0.0.0.0 --port 4096`

### `openchamber`

Sorumluluklar:

- web arayüzünü sunmak
- repo içindeki submodule source tree'den build edilmek
- GitHub authentication akışını başlatmak ve yönetmek
- repository klonlama ve görsel çalışma akışlarını sağlamak
- OpenCode backend'ine istemci olarak bağlanmak
- kendi config ve UI state verisini kalıcı volume'lerde tutmak

## Volume ve Kalıcılık Tasarımı

Üç kalıcılık alanı beklenir:

1. OpenCode config/state
2. OpenChamber config/state
3. Ortak workspace

Dokploy volume yönetimini üstleneceği için compose tasarımı bu depolama alanlarını servisler arasında doğru paylaştırmaya odaklanır.

Beklenen davranışlar:

- OpenCode config/state yeniden deploy sonrası korunur
- OpenChamber config/state yeniden deploy sonrası korunur
- GitHub auth ile ilgili kalıcı kullanıcı durumu OpenChamber tarafında mümkün olduğunca korunur
- Workspace içindeki klonlanan repository'ler yeniden deploy sonrası kaybolmaz

SSH anahtarı veya `.ssh` mount tasarımın parçası değildir.

## Environment Variable Modeli

`.env.example` içinde en az şu gruplar yer almalıdır:

### OpenChamber

- `UI_PASSWORD`
- `OPENCODE_HOST`
- `OPENCODE_SKIP_START`

### OpenCode

- `OPENCODE_SERVER_PASSWORD`
- `OPENCODE_SERVER_USERNAME` (opsiyonel)
- `OPENAI_API_KEY` (opsiyonel, kullanılan sağlayıcıya göre)
- `ANTHROPIC_API_KEY` (opsiyonel, kullanılan sağlayıcıya göre)
- diğer sağlayıcılara ait opsiyonel anahtarlar

### Notlar

- Compose dosyası değerleri environment variable'lar üzerinden okumalıdır.
- Gerçek secret değerler repo içine yazılmamalıdır.
- Dokploy arayüzünde `.env.example` referans alınarak gerçek environment variable değerleri tanımlanacaktır.
- OpenChamber image referansı environment variable ile taşınmayacaktır; servis local build kullanacaktır.

## Startup ve Bootstrap Akışı

### `opencode` başlangıcı

Container başlarken hafif bir bootstrap akışı yürütülür:

1. Config dizinleri kontrol edilir
2. Yoksa varsayılan temel config hazırlanır
3. `oh-my-opencode-slim` için gereken plugin/config bağlantıları doğrulanır
4. Mevcut kullanıcı config'i varsa korunur, gereksiz overwrite yapılmaz
5. Sonrasında OpenCode server başlatılır

Bootstrap akışı fail-fast olmalıdır. Plugin/config kurulumu eksikse container başarısız olmalı ve log'da neden anlaşılmalıdır.

### `openchamber` başlangıcı

Container şu ilkelere göre başlar:

- embedded OpenCode başlatması kapatılır
- harici backend olarak `http://opencode:4096` kullanılır
- UI servisi public erişim için Dokploy tarafından yayınlanabilir durumda çalışır

## Ağ ve Bağlantı Modeli

- Her iki servis aynı compose stack içinde bulunur
- OpenChamber, OpenCode'a servis adı üzerinden bağlanır
- OpenCode public giriş noktası olarak tasarlanmaz
- Dış erişim noktası OpenChamber'dir
- Traefik label ve domain routing ayrıntıları Dokploy tarafından yönetilir; compose tasarımının esas odağı servislerin birbirini bulabilmesidir

## Güvenlik Sınırları

- Public yüz sadece OpenChamber'dir
- OpenCode backend rolünde kalır
- SSH mount kullanılmaz
- Secret'lar image içine bake edilmez
- Kullanıcıya özel bilgiler runtime environment ve kalıcı volume alanlarında tutulur
- OpenCode backend için server password aktif kalır
- OpenChamber için UI password aktif kalır

Bu sınırlar uzak VDS üzerinde public erişim verilen bir Dokploy dağıtımı için saldırı yüzeyini gereksiz yere büyütmemeyi amaçlar.

## Hata Yönetimi

### Servis bağımlılığı

- `openchamber`, `opencode` hazır olmadan başlayabilir; bu durumda başlangıç düzeni ve mümkün olan ölçüde readiness/health yaklaşımı düşünülmelidir
- `opencode` hazır değilse bunun UI ve log seviyesinde teşhis edilebilir olması gerekir

### Bootstrap hataları

- `oh-my-opencode-slim` kurulumu veya plugin bağlanması başarısız olursa `opencode` container fail-fast davranmalıdır
- Sorun log çıktısından anlaşılabilir olmalıdır

### GitHub auth hataları

- GitHub authentication başarısızlığı tüm stack'i düşürmemelidir
- Sorun OpenChamber UI akışında izole kalmalıdır

## Doğrulama Stratejisi

Çözüm tamamlandığında şu seviyelerde doğrulama yapılmalıdır:

### Build doğrulaması

- `opencode` custom image başarıyla build oluyor mu
- `oh-my-opencode-slim` image içinde gerçekten kurulmuş mu

### Container doğrulaması

- compose ile her iki servis birlikte kalkıyor mu
- `openchamber`, `opencode` servisine ağ üzerinden erişebiliyor mu

### Fonksiyonel doğrulama

- OpenChamber arayüzü erişilebilir mi
- GitHub auth akışı UI üzerinden başlatılabiliyor mu
- repository ortak workspace volume'üne klonlanabiliyor mu
- OpenCode bu workspace üzerinde çalışabiliyor mu

### Kalıcılık doğrulaması

- yeniden başlatma veya yeniden deploy sonrası config/state korunuyor mu
- workspace içeriği korunuyor mu

## Kabul Kriterleri

Bir çözümün bu tasarıma uygun sayılması için aşağıdakilerin sağlanması gerekir:

- Repo içinde tek bir `docker-compose.yml` bulunur
- `opencode` servisi custom Dockerfile ile build edilir
- `oh-my-opencode-slim` `opencode` image'ında preinstalled gelir
- `openchamber` ayrı servis olarak çalışır
- `openchamber` servisinin backend'i `opencode` servisidir
- iki servis ortak workspace volume'ünü paylaşır
- GitHub entegrasyonu OpenChamber UI üzerinden yapılabilir
- repo içinde `.env.example` dosyası bulunur
- çözüm Dokploy üzerinde compose stack olarak deploy edilmeye uygundur

## Uygulama İçin Önerilen Dosya Yapısı

Beklenen minimum dosyalar:

- `docker-compose.yml`
- `Dockerfile.opencode` veya benzer adlandırılmış custom OpenCode Dockerfile'ı
- `scripts/` altında gerekiyorsa bootstrap/entrypoint script'leri
- `.env.example`
- kısa kullanım notları için `README.md`

Bu dosya yapısı implementation plan aşamasında kesinleştirilecektir.

## Tercih Edilen Uygulama Yolu

Seçilen yaklaşım şudur:

- iki servisli compose tasarımı
- custom OpenCode image
- plugin'in image içine preinstalled eklenmesi
- OpenChamber'in ayrı servis olarak kullanılması
- paylaşılan workspace volume
- `.env.example` tabanlı environment yönetimi
- GitHub entegrasyonunun yalnızca OpenChamber UI üzerinden yapılması

Bu yaklaşım, Dokploy üzerinde sade kurulum, sürdürülebilir bakım ve web odaklı kullanım beklentileri arasında en dengeli seçenektir.
