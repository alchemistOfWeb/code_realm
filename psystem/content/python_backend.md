# Python Backend — карта знаний

> Бэкенд-разработка на Python: от HTTP до системного дизайна.
> Ориентир — собеседования Junior/Middle Python Backend Developer.

---

## Сеть и HTTP <!-- difficulty: 1 -->

### Что происходит, когда вводишь URL в браузере

1. **DNS**: домен → IP-адрес (кэш браузера → ОС → резолвер → корневые/TLD/авторитативные серверы).
2. **TCP**: трёхэтапное рукопожатие SYN → SYN-ACK → ACK.
3. **TLS**: обмен ключами, проверка сертификата, шифрованный канал (HTTPS).
4. **HTTP-запрос** → балансировщик → веб-сервер (nginx) → приложение (uvicorn/gunicorn) → БД.
5. Ответ, рендер страницы, дополнительные запросы за статикой.

Классический вопрос, по нему проверяют широту кругозора.

<!-- quiz: Что происходит первым при открытии https://example.com? | +DNS-резолвинг домена в IP | TLS-рукопожатие | HTTP-запрос GET | Рендер страницы -->

### HTTP: методы, статусы, заголовки

| Метод | Назначение | Идемпотентен |
|---|---|---|
| GET | получить ресурс | да |
| POST | создать / действие | нет |
| PUT | заменить целиком | да |
| PATCH | частично изменить | не обязательно |
| DELETE | удалить | да |

Статусы: **2xx** успех (200, 201 Created, 204 No Content), **3xx** редиректы (301, 302, 304), **4xx** ошибка клиента (400, 401, 403, 404, 409, 422, 429), **5xx** ошибка сервера (500, 502, 503, 504).

Заголовки: `Content-Type`, `Authorization`, `Cache-Control`, `ETag`, `Location`.

**На собесе:** разница 401 и 403? PUT и PATCH? Что такое идемпотентность и зачем она нужна (ретраи)?

<!-- quiz: Чем 401 отличается от 403? | +401 — не аутентифицирован, 403 — аутентифицирован, но нет прав | Ничем | 401 — нет ресурса, 403 — ошибка сервера | 403 — неверный пароль, 401 — бан -->
<!-- quiz: Какой из методов НЕ идемпотентен? | +POST | GET | PUT | DELETE -->

### HTTP/1.1, HTTP/2, HTTP/3, WebSocket

- HTTP/1.1: keep-alive, но один запрос за раз на соединение.
- HTTP/2: мультиплексирование потоков в одном TCP-соединении, сжатие заголовков.
- HTTP/3: поверх QUIC (UDP), нет head-of-line blocking на уровне TCP.
- **WebSocket** — постоянное двунаправленное соединение (чаты, live-обновления); альтернатива — SSE (только сервер → клиент).

### Cookies, сессии и CORS

- **Cookie** — данные, которые браузер хранит и отправляет с каждым запросом к домену. Флаги: `HttpOnly`, `Secure`, `SameSite`.
- **Сессия** — состояние на сервере, в cookie только session id.
- **CORS** — механизм браузера, разрешающий запросы с другого origin. Сервер отвечает заголовками `Access-Control-Allow-Origin`; для «сложных» запросов браузер шлёт preflight `OPTIONS`.

<!-- quiz: Кто применяет политику CORS? | +Браузер | Сервер базы данных | DNS | Балансировщик нагрузки -->

---

## Проектирование API <!-- difficulty: 1 -->

### Принципы REST

- Ресурсы — существительные: `/users/42/orders`, а не `/getUserOrders`.
- Действия — HTTP-методами; stateless (каждый запрос самодостаточен).
- Правильные статус-коды и единый формат ошибок.
- Вложенность — не глубже 2 уровней.

```text
GET    /api/v1/orders?status=paid&limit=20&cursor=abc
POST   /api/v1/orders            → 201 + Location: /api/v1/orders/17
PATCH  /api/v1/orders/17
DELETE /api/v1/orders/17         → 204
```

### Пагинация, фильтрация, версионирование, ошибки

- **Пагинация**: offset/limit (просто, но медленно на больших offset и «прыгает» при вставках) vs **cursor/keyset** (`WHERE id > last_id`, стабильно и быстро).
- **Версионирование**: в URL (`/v1/`) или в заголовке.
- **Ошибки**: единый формат, например RFC 7807 (`type`, `title`, `detail`).
- **Идемпотентные POST**: заголовок `Idempotency-Key` для платежей.

<!-- quiz: Чем cursor/keyset-пагинация лучше offset на больших таблицах? | +Не сканирует пропущенные строки и стабильна при вставках | Позволяет прыгнуть на любую страницу | Проще в реализации | Не требует индексов -->

### OpenAPI и документация

OpenAPI (Swagger) — машиночитаемая спецификация API. FastAPI генерирует её автоматически (`/docs`, `/redoc`). Из спецификации можно генерировать клиентов и контрактные тесты.

### GraphQL и gRPC <!-- optional -->

- **GraphQL**: клиент сам выбирает поля, один endpoint, нет over/under-fetching; сложнее кэширование и защита от тяжёлых запросов.
- **gRPC**: бинарный protobuf поверх HTTP/2, строгие контракты, стриминг; популярен для межсервисного взаимодействия.

---

## FastAPI <!-- difficulty: 2 -->

Современный async-фреймворк: типы → валидация → документация.

### Роуты, Pydantic-модели и валидация

```python
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field

app = FastAPI()

class ItemIn(BaseModel):
    name: str = Field(min_length=1)
    price: float = Field(gt=0)

class ItemOut(ItemIn):
    id: int

@app.post("/items", response_model=ItemOut, status_code=status.HTTP_201_CREATED)
async def create_item(item: ItemIn):
    return await repo.create(item)

@app.get("/items/{item_id}")
async def get_item(item_id: int):
    item = await repo.get(item_id)
    if item is None:
        raise HTTPException(404, "Item not found")
    return item
```

Ошибка валидации → автоматический ответ **422** с описанием полей.

<!-- quiz: Какой статус возвращает FastAPI при ошибке валидации тела запроса? | +422 | 400 | 500 | 404 -->

### Dependency Injection

```python
from fastapi import Depends

async def get_db():
    async with SessionLocal() as session:
        yield session            # закрытие после ответа

async def get_current_user(token: str = Depends(oauth2_scheme), db=Depends(get_db)):
    ...

@app.get("/me")
async def me(user: User = Depends(get_current_user)):
    return user
```

Зависимости кэшируются в рамках запроса, легко подменяются в тестах: `app.dependency_overrides[get_db] = fake_db`.

### async def vs def в FastAPI

- `async def` — выполняется в event loop; внутри **нельзя** блокирующие вызовы (requests, синхронный драйвер БД).
- `def` — FastAPI запускает в threadpool, блокирующий код допустим.
- Тяжёлые CPU-задачи — в отдельный процесс или очередь задач.

**На собесе:** что будет, если в `async def` сделать синхронный запрос к БД? (→ заблокирует все запросы воркера)

<!-- quiz: Что сделает FastAPI с обычной def-функцией роута? | +Выполнит её в пуле потоков | Выполнит прямо в event loop | Откажется регистрировать | Сделает её корутиной автоматически -->

### Middleware, обработка ошибок, фоновые задачи, lifespan

```python
@app.middleware("http")
async def timing(request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    response.headers["X-Process-Time"] = f"{time.perf_counter() - start:.3f}"
    return response

@app.exception_handler(AppError)
async def app_error_handler(request, exc): ...

@app.post("/signup")
async def signup(bg: BackgroundTasks): bg.add_task(send_email, ...)
```

`lifespan` — инициализация и закрытие пулов соединений при старте/остановке приложения.

---

## Django <!-- difficulty: 2 -->

«Батарейки в комплекте»: ORM, админка, миграции, auth, шаблоны.

### MVT, приложения и ORM

- **Model** — данные, **View** — логика, **Template** — представление (аналог MVC).
- Проект состоит из приложений (`apps`), конфигурация — в `settings.py`.
- Миграции: `makemigrations` → `migrate`.

```python
class Order(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="orders")
    total = models.DecimalField(max_digits=10, decimal_places=2)
    created = models.DateTimeField(auto_now_add=True)

Order.objects.filter(total__gt=100).order_by("-created")[:10]
```

QuerySet ленивый: запрос выполняется при итерации, срезе, `list()`, `len()`.

### Проблема N+1 и оптимизация запросов

```python
for order in Order.objects.all():
    print(order.user.email)          # +1 запрос на каждый заказ!

Order.objects.select_related("user")      # JOIN — для FK / OneToOne
User.objects.prefetch_related("orders")   # отдельный запрос + склейка в Python — для M2M / обратных FK
```

Также: `only()`/`defer()`, `values()`, `annotate()`/`aggregate()`, `F()`/`Q()`-выражения, `bulk_create`. Инструмент — django-debug-toolbar.

**На собесе:** что такое N+1? Разница select_related и prefetch_related?

<!-- quiz: Что использовать в Django для ForeignKey, чтобы избежать N+1? | +select_related | prefetch_related для FK обязательно | only() | values_list() -->
<!-- quiz: Как Django выполняет prefetch_related? | +Отдельным запросом и склейкой в Python | Через JOIN | Через подзапрос в WHERE | Кэшированием в Redis -->

### Django REST Framework

Serializers (валидация и преобразование), ViewSets + Routers, permissions, throttling, пагинация, аутентификация (Session, Token, JWT).

### Сигналы, middleware, кэш Django <!-- optional -->

- Сигналы (`post_save`) удобны, но скрывают логику — лучше явный вызов сервиса.
- Middleware — обработка каждого запроса/ответа.
- Кэш-фреймворк: per-view, низкоуровневый `cache.get/set`, бэкенд Redis.

---

## Базы данных и SQL <!-- difficulty: 1 -->

### Реляционная модель и нормализация

- Таблицы, строки, столбцы; **первичный ключ** (PK), **внешний ключ** (FK) и ограничения целостности.
- Связи: 1:1, 1:N, M:N (через связующую таблицу).
- Нормальные формы: 1НФ (атомарность), 2НФ (нет зависимости от части ключа), 3НФ (нет транзитивных зависимостей).
- Денормализация — осознанное дублирование ради скорости чтения.

### SQL: SELECT, JOIN, GROUP BY

```sql
SELECT u.name, COUNT(o.id) AS orders, SUM(o.total) AS revenue
FROM users u
LEFT JOIN orders o ON o.user_id = u.id AND o.status = 'paid'
WHERE u.created_at >= '2026-01-01'
GROUP BY u.id, u.name
HAVING COUNT(o.id) > 3
ORDER BY revenue DESC
LIMIT 10;
```

- `INNER JOIN` — только совпадения, `LEFT JOIN` — все слева + совпадения справа.
- `WHERE` фильтрует строки до группировки, `HAVING` — группы после.
- Порядок выполнения: FROM → JOIN → WHERE → GROUP BY → HAVING → SELECT → ORDER BY → LIMIT.
- Оконные функции: `ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC)`.

**На собесе:** напиши запрос «топ-3 покупателя по сумме за месяц»; разница WHERE и HAVING; найди дубликаты email.

<!-- quiz: Чем WHERE отличается от HAVING? | +WHERE фильтрует строки до группировки, HAVING — группы после | Ничем | HAVING быстрее | WHERE работает только с JOIN -->
<!-- quiz: Что вернёт LEFT JOIN для строки слева без совпадения справа? | +Строку слева с NULL в колонках правой таблицы | Ничего | Ошибку | Строку справа -->

### Индексы и EXPLAIN

- **B-tree** — индекс по умолчанию: поиск по равенству, диапазону, сортировка. O(log n).
- Составной индекс `(a, b)` работает для `a` и `a + b`, но не для одного `b` (правило левого префикса).
- Hash, GIN (jsonb, полнотекстовый поиск), GiST, частичные и покрывающие индексы.
- Цена индекса: медленнее запись, больше места.
- `EXPLAIN ANALYZE` — план запроса: Seq Scan vs Index Scan, реальное время.

<!-- quiz: Есть составной индекс (a, b). Какой запрос НЕ сможет эффективно его использовать? | +WHERE b = 1 | WHERE a = 1 | WHERE a = 1 AND b = 2 | ORDER BY a, b -->

### Транзакции, ACID и уровни изоляции

**ACID**: Atomicity (всё или ничего), Consistency (ограничения соблюдены), Isolation (транзакции не мешают друг другу), Durability (закоммиченное не теряется).

| Уровень изоляции | Грязное чтение | Неповторяемое чтение | Фантомы |
|---|---|---|---|
| Read Uncommitted | возможно | возможно | возможно |
| Read Committed (Postgres по умолчанию) | нет | возможно | возможно |
| Repeatable Read | нет | нет | возможно* |
| Serializable | нет | нет | нет |

*В Postgres Repeatable Read на основе снимков не допускает и фантомов.

Блокировки: `SELECT ... FOR UPDATE`, оптимистичная блокировка (поле `version`), deadlock.

<!-- quiz: Что означает буква A в ACID? | +Atomicity — всё или ничего | Availability — доступность | Accuracy — точность | Asynchrony — асинхронность -->
<!-- quiz: Какой уровень изоляции используется в PostgreSQL по умолчанию? | +Read Committed | Serializable | Repeatable Read | Read Uncommitted -->

### PostgreSQL: полезные возможности

`jsonb`, массивы, `UPSERT` (`INSERT ... ON CONFLICT`), CTE (`WITH`), материализованные представления, `LISTEN/NOTIFY`, MVCC и `VACUUM`, пул соединений PgBouncer.

---

## SQLAlchemy и миграции <!-- difficulty: 2 -->

### Core vs ORM, Session и Unit of Work

```python
from sqlalchemy import select
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

class Base(DeclarativeBase): ...

class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(unique=True)
    orders: Mapped[list["Order"]] = relationship(back_populates="user")

async with async_session() as session:
    user = await session.scalar(select(User).where(User.email == email))
    session.add(Order(user=user, total=10))
    await session.commit()
```

**Session** реализует Unit of Work: копит изменения и отправляет их одной транзакцией при `flush`/`commit`. Identity Map — один объект на одну строку в рамках сессии.

<!-- quiz: Какой паттерн реализует Session в SQLAlchemy? | +Unit of Work | Singleton | Active Record | Observer -->

### Загрузка связей: lazy vs eager

- `lazy` (по умолчанию) — запрос при обращении к атрибуту → N+1; в async-режиме вызывает ошибку.
- `selectinload` — отдельный `SELECT ... WHERE id IN (...)`, хорош для коллекций.
- `joinedload` — JOIN, хорош для many-to-one.

```python
await session.scalars(select(User).options(selectinload(User.orders)))
```

<!-- quiz: Какой способ загрузки лучше для коллекций (one-to-many) в SQLAlchemy? | +selectinload | lazy | joinedload всегда | noload -->

### Alembic: миграции схемы

```bash
alembic revision --autogenerate -m "add orders table"
alembic upgrade head
alembic downgrade -1
```

Правила: миграции — в git, проверять автогенерацию руками, data-миграции отдельно, изменения схемы в проде — обратносовместимые (expand → migrate → contract).

---

## Кэширование и NoSQL <!-- difficulty: 2 -->

### Redis

In-memory хранилище «ключ → структура данных», однопоточное ядро, операции атомарны.

- Типы: string, hash, list, set, sorted set, stream, HyperLogLog.
- Применение: кэш, сессии, rate limiting, очереди, лидерборды (sorted set), pub/sub, распределённые блокировки.
- `EXPIRE`/TTL, политики вытеснения (`allkeys-lru`), персистентность RDB/AOF.

```python
await redis.set(f"user:{id}", payload, ex=300)
await redis.incr(f"rate:{ip}:{minute}")
```

<!-- quiz: Какая структура Redis лучше всего подходит для лидерборда? | +Sorted set | List | String | HyperLogLog -->

### Стратегии кэширования и инвалидация

- **Cache-aside** (lazy loading): читаем кэш → промах → БД → пишем в кэш. Самая распространённая.
- **Write-through**: пишем в кэш и БД синхронно. **Write-back**: сначала кэш, БД — позже.
- Инвалидация: TTL, удаление ключа при изменении, версионирование ключей.
- **Cache stampede** — множество одновременных промахов: блокировка на перестроение, ранний случайный рефреш.

«В информатике две сложные вещи: инвалидация кэша и придумывание имён».

<!-- quiz: Как работает cache-aside? | +Читаем кэш, при промахе — БД, затем записываем результат в кэш | Пишем только в кэш, в БД — позже | Кэш сам ходит в БД | Каждый запрос идёт сразу в БД -->

### Документные и другие NoSQL БД

- **MongoDB** — документы JSON/BSON, гибкая схема, горизонтальное шардирование.
- **Cassandra** — wide-column, огромные объёмы записи.
- **Elasticsearch** — полнотекстовый поиск и аналитика логов.
- Когда SQL, когда NoSQL: строгие связи и транзакции → SQL; гибкая схема, масштаб записи, специфичные запросы → NoSQL.

---

## Очереди и фоновые задачи <!-- difficulty: 2 -->

### Celery и брокеры сообщений

```python
from celery import Celery
app = Celery("tasks", broker="redis://localhost:6379/0")

@app.task(bind=True, max_retries=3, acks_late=True)
def send_email(self, user_id):
    try:
        ...
    except SMTPError as e:
        raise self.retry(exc=e, countdown=2 ** self.request.retries)
```

Зачем: отправка писем, обработка файлов, долгие вычисления вне HTTP-запроса. Альтернативы: RQ, Dramatiq, arq (async), Taskiq.

### RabbitMQ vs Kafka

| | RabbitMQ | Kafka |
|---|---|---|
| Модель | очереди, брокер «пушит» | лог событий, consumer «тянет» |
| Сообщение после чтения | удаляется (ack) | хранится, можно перечитать |
| Сильная сторона | маршрутизация, задачи | стриминг, огромный поток событий |

Паттерны: point-to-point, pub/sub, event sourcing, outbox pattern.

<!-- quiz: Чем Kafka принципиально отличается от классической очереди? | +Хранит лог событий, сообщения можно перечитать | Удаляет сообщение сразу после доставки | Работает только в памяти | Не поддерживает несколько consumer'ов -->

### Надёжность: at-least-once, идемпотентность, DLQ

- Гарантии доставки: at-most-once, **at-least-once** (стандарт), exactly-once (дорого).
- При at-least-once сообщение может прийти дважды → обработчик должен быть **идемпотентным** (дедупликация по id).
- Ретраи с экспоненциальной задержкой; после N неудач — **Dead Letter Queue**.
- **Transactional outbox**: событие пишется в таблицу в той же транзакции, что и данные, затем публикуется отдельным процессом.

<!-- quiz: Почему consumer при доставке at-least-once должен быть идемпотентным? | +Сообщение может прийти повторно | Чтобы работал быстрее | Иначе брокер не подключится | Это нужно только для Kafka -->

---

## Аутентификация и безопасность <!-- difficulty: 2 -->

### Аутентификация, авторизация, хранение паролей

- **Аутентификация** — кто ты (логин), **авторизация** — что тебе можно (роли, права).
- Пароли — только **хеш с солью** медленной функцией: bcrypt, argon2, scrypt. Не MD5/SHA-256 «как есть».
- Модели прав: RBAC (роли), ABAC (атрибуты), проверка владельца ресурса.

<!-- quiz: Как правильно хранить пароли? | +Хеш медленной функцией с солью (bcrypt, argon2) | MD5 без соли | В зашифрованном виде AES | Base64 -->

### JWT и OAuth2

- **JWT** = header.payload.signature (base64url). Подписан, но **не зашифрован** — не кладите секреты.
- Access token короткоживущий (минуты), refresh token долгоживущий, хранится безопасно, ротация.
- Отозвать JWT до истечения нельзя без blacklist — это плата за stateless.
- **OAuth2** — делегирование доступа (вход через Google): Authorization Code + PKCE; **OpenID Connect** добавляет идентификацию (id_token).

**На собесе:** где хранить JWT на фронтенде (httpOnly cookie vs localStorage)? Как работает refresh?

<!-- quiz: Зашифровано ли содержимое (payload) обычного JWT? | +Нет, только подписано — его можно прочитать | Да, всегда | Да, если используется HTTPS | Только поле exp -->

### OWASP Top 10

- **SQL-инъекции** → параметризованные запросы / ORM, никогда f-строки в SQL.
- **XSS** → экранирование вывода, CSP.
- **CSRF** → SameSite cookie, CSRF-токены.
- Broken access control (IDOR: `/orders/17` чужого пользователя), SSRF, небезопасная десериализация (`pickle` от пользователя).
- Секреты — в переменных окружения / vault, не в git. HTTPS везде, rate limiting на логин.

<!-- quiz: Как защититься от SQL-инъекций? | +Параметризованные запросы / ORM | Экранировать кавычки вручную | Использовать POST вместо GET | Хранить БД на отдельном сервере -->

---

## Docker и деплой <!-- difficulty: 2 -->

### Docker: образ, контейнер, слои

- **Образ** — неизменяемый шаблон из слоёв; **контейнер** — запущенный экземпляр образа.
- Контейнер ≠ виртуальная машина: общее ядро ОС, изоляция через namespaces и cgroups.

```dockerfile
FROM python:3.12-slim AS base
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN pip install uv && uv sync --frozen --no-dev    # слой зависимостей кэшируется
COPY . .
USER 1000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

Оптимизации: порядок слоёв (зависимости до кода), `.dockerignore`, multi-stage сборка, slim/alpine-образы, запуск не от root.

<!-- quiz: Чем контейнер отличается от виртуальной машины? | +Использует ядро хоста, изоляция через namespaces и cgroups | Эмулирует всё железо | Ничем | Работает только на Linux-хосте без ядра -->
<!-- quiz: Почему в Dockerfile зависимости копируют и ставят до копирования кода? | +Чтобы слой зависимостей кэшировался при изменении кода | Так требует синтаксис | Чтобы образ стал меньше | Иначе pip не работает -->

### docker-compose

```yaml
services:
  api:
    build: .
    env_file: .env
    depends_on: [db, redis]
    ports: ["8000:8000"]
  db:
    image: postgres:16
    volumes: [pgdata:/var/lib/postgresql/data]
  redis:
    image: redis:7
volumes:
  pgdata:
```

Сети, тома (volumes) для данных, healthcheck, переменные окружения.

### Серверы приложений: WSGI/ASGI, gunicorn, uvicorn, nginx

- **WSGI** — синхронный интерфейс (Django, Flask), **ASGI** — асинхронный (FastAPI, WebSocket).
- `gunicorn -k uvicorn.workers.UvicornWorker -w 4` — несколько процессов-воркеров (обход GIL).
- **nginx** перед приложением: TLS, статика, reverse proxy, балансировка, буферизация, лимиты.

<!-- quiz: Какой интерфейс нужен для FastAPI и WebSocket? | +ASGI | WSGI | CGI | FastCGI -->

### CI/CD

Пайплайн: линтеры → тесты → сборка образа → пуш в registry → деплой (staging → prod). Инструменты: GitHub Actions, GitLab CI. Стратегии деплоя: rolling, blue-green, canary. Миграции БД — отдельным шагом перед переключением трафика.

---

## Тестирование бэкенда <!-- difficulty: 2 -->

### Unit и интеграционные тесты API

```python
from httpx import AsyncClient, ASGITransport

async def test_create_item(db_session):
    app.dependency_overrides[get_db] = lambda: db_session
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        resp = await client.post("/items", json={"name": "A", "price": 10})
    assert resp.status_code == 201
```

- Тестовая БД: отдельная база, транзакция с откатом после каждого теста, testcontainers.
- Внешние HTTP-сервисы — мокать (respx, responses), очереди — in-memory.
- factory_boy / polyfactory — генерация тестовых данных.

### Нагрузочное тестирование <!-- optional -->

Locust, k6, wrk: RPS, латентность p50/p95/p99, поиск узких мест (БД, пул соединений, CPU воркеров).

---

## Архитектура и системный дизайн <!-- difficulty: 3 -->

### Монолит vs микросервисы

- **Монолит**: проще разработка, деплой и транзакции; сложнее масштабировать команды.
- **Микросервисы**: независимый деплой и масштабирование; цена — сеть, распределённые транзакции (саги), наблюдаемость, DevOps.
- Разумный путь: **модульный монолит** → выделение сервисов по необходимости.

<!-- quiz: Главная цена перехода на микросервисы? | +Сеть, распределённые транзакции и сложность эксплуатации | Невозможность масштабирования | Один язык на всё | Отсутствие API -->

### Масштабирование

- **Вертикальное** (мощнее сервер) vs **горизонтальное** (больше серверов за балансировщиком).
- Stateless-приложения масштабируются легко: состояние — в БД/Redis.
- БД: реплики для чтения, партиционирование, **шардирование**, пул соединений.
- CDN для статики, кэш на каждом уровне, асинхронная обработка через очереди.

<!-- quiz: Какие приложения проще всего масштабировать горизонтально? | +Stateless — состояние хранится во внешних хранилищах | Stateful с локальными сессиями | Только монолиты | Приложения без БД -->

### CAP-теорема и консистентность

При сетевом разделении (P) система выбирает: **консистентность** (C) или **доступность** (A). Eventual consistency — данные согласуются со временем (реплики, кэши, события).

<!-- quiz: Что выбирает система по CAP при сетевом разделении? | +Между консистентностью и доступностью | Между скоростью и ценой | Между SQL и NoSQL | Ничего не нужно выбирать -->

### Чистая архитектура и слои

```text
api (роуты, схемы) → services (бизнес-логика) → repositories (доступ к данным) → db
```

Зависимости направлены внутрь, бизнес-логика не знает о FastAPI и SQL. Паттерны: Repository, Unit of Work, Service Layer, DI. Это делает код тестируемым.

### Наблюдаемость и надёжность

- **Логи** (структурированные, JSON, correlation id), **метрики** (Prometheus + Grafana: RPS, ошибки, латентность), **трейсинг** (OpenTelemetry).
- Health checks, graceful shutdown, таймауты на все внешние вызовы, circuit breaker, rate limiting (token bucket).
- SLI/SLO, алерты по симптомам.

### Как проходить system design интервью

1. Уточни требования: функциональные, нагрузка (RPS, объём данных), задержки.
2. Оцени масштаб «на салфетке».
3. Нарисуй high-level схему: клиент → балансировщик → сервисы → хранилища → очереди.
4. Схема данных и API.
5. Узкие места, масштабирование, отказоустойчивость, компромиссы.

Типовые задачи: URL shortener, лента новостей, чат, rate limiter.

---

## Linux для бэкендера <!-- difficulty: 1, optional -->

### Базовые команды и процессы

```bash
ls -la, cd, grep -rn "error" logs/, tail -f app.log, less, find . -name "*.py"
ps aux | grep uvicorn, top/htop, kill -15 PID, systemctl status nginx, journalctl -u app
df -h, du -sh *, free -m, ss -tlnp, curl -v http://localhost:8000/health
chmod 644 file, chown user:group file, ssh, scp, crontab -e
```

Сигналы: SIGTERM (вежливо завершиться, graceful shutdown), SIGKILL (убить немедленно), SIGHUP (перечитать конфиг).
