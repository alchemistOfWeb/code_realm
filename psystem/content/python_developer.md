# Python Developer — карта знаний

> Программа подготовки к собеседованию на Python-разработчика (Junior → Middle).
> Каждый подраздел: короткая теория, пример кода и вопросы, которые реально задают.

---

## Как работает Python <!-- difficulty: 1 -->

Python — интерпретируемый язык с динамической строгой типизацией. Основная реализация — **CPython** (написан на C).

### Интерпретатор, байткод и CPython

Исходный `.py` компилируется в **байткод** (`.pyc` в `__pycache__`), который исполняет виртуальная машина CPython — стековая машина, выполняющая инструкцию за инструкцией.

```python
import dis
def add(a, b):
    return a + b
dis.dis(add)   # LOAD_FAST a, LOAD_FAST b, BINARY_OP +, RETURN_VALUE
```

Другие реализации: **PyPy** (JIT, быстрее на долгих вычислениях), Jython, MicroPython.

**На собесе:**
- Python компилируемый или интерпретируемый? → и то, и другое: компиляция в байткод + интерпретация.
- Что такое `.pyc` и зачем `__pycache__`?

<!-- quiz: Во что CPython компилирует исходный .py перед выполнением? | +В байткод для виртуальной машины CPython | Сразу в машинный код процессора | В JavaScript | Ни во что — читает текст построчно || Байткод кэшируется в __pycache__/*.pyc и исполняется стековой ВМ. -->

### Динамическая строгая типизация

- **Динамическая** — тип у объекта, а не у переменной; проверяется во время выполнения.
- **Строгая** — нет неявных преобразований: `"1" + 1` → `TypeError`.
- **Утиная типизация** — «если крякает как утка — это утка»: важны методы объекта, а не его класс.

```python
x = 10        # x ссылается на int
x = "text"    # теперь на str — это нормально
len([1, 2]), len("ab"), len({1: 2})  # len работает со всем, у чего есть __len__
```

<!-- quiz: Что произойдёт при выполнении "1" + 1? | +TypeError | Результат "11" | Результат 2 | SyntaxError || Строгая типизация: неявного приведения str и int нет. -->

### Всё — объект: имена и ссылки

Переменная — это **имя**, привязанное к объекту. У каждого объекта есть `id` (идентичность), тип и значение.

```python
a = [1, 2]
b = a           # b ссылается на тот же список
b.append(3)
print(a)        # [1, 2, 3]
a == b, a is b  # (True, True)
[1] == [1], [1] is [1]   # (True, False)
```

- `==` сравнивает значения (`__eq__`), `is` — идентичность (`id`).
- `is` используют для синглтонов: `x is None`.
- Малые int (−5…256) и короткие строки **интернируются** — `is` может «случайно» работать, полагаться на это нельзя.

**На собесе:** разница `is` и `==`? Почему `a = b = []` опасно?

<!-- quiz: Чем отличается is от ==? | +is сравнивает идентичность объектов, == — значения | is быстрее и всегда предпочтительнее | Ничем, это синонимы | == сравнивает id объектов || Для None используют is, для значений — ==. -->

### Изменяемые и неизменяемые типы

| Неизменяемые (immutable) | Изменяемые (mutable) |
|---|---|
| int, float, bool, str, tuple, frozenset, bytes | list, dict, set, bytearray, пользовательские объекты |

«Изменение» неизменяемого объекта создаёт новый объект:

```python
s = "abc"
print(id(s)); s += "d"; print(id(s))   # id разные
t = ([1], 2)
t[0].append(5)    # можно! кортеж неизменяем, но содержит изменяемый список
```

Только неизменяемые (точнее, **хешируемые**) объекты могут быть ключами dict и элементами set.

**На собесе:** можно ли использовать tuple как ключ словаря? А tuple со списком внутри?

<!-- quiz: Какой из типов изменяемый? | +list | tuple | str | frozenset -->
<!-- quiz: Может ли tuple, содержащий list, быть ключом dict? | Да, tuple всегда хешируем | +Нет — элемент-список делает его нехешируемым | Да, если список пустой | Только в Python 2 -->

---

## Встроенные типы и коллекции <!-- difficulty: 1 -->

Знание сложности операций над коллекциями — обязательный минимум для собеса.

### Числа и строки

- `int` — произвольной точности (нет переполнения).
- `float` — IEEE 754 double: `0.1 + 0.2 != 0.3`. Для денег — `decimal.Decimal`.
- `//` — целочисленное деление (округление вниз), `%` — остаток, `divmod(a, b)`.
- `str` — неизменяемая последовательность Unicode-символов. Склеивать много строк — через `"".join(parts)`, а не `+=` в цикле.

```python
f"{price:.2f} руб, {name!r}, {value:>10}"   # f-строки
"a,b,c".split(","), " x ".strip(), "abc"[::-1]
```

### list и tuple

`list` — динамический массив указателей.

| Операция | Сложность |
|---|---|
| `lst[i]`, `append`, `pop()` | O(1) (append — амортизированно) |
| `insert(0, x)`, `pop(0)`, `x in lst` | O(n) |
| `sort()` | O(n log n), Timsort, стабильная |

`tuple` — неизменяемый, легче по памяти, хешируемый (если элементы хешируемы). Используется для «записей» фиксированной структуры и как ключ dict.

```python
a, *rest = [1, 2, 3, 4]   # распаковка: a=1, rest=[2,3,4]
point = (3, 4)
```

**На собесе:** почему `pop(0)` медленный и что использовать вместо (→ `collections.deque`)?

<!-- quiz: Какова сложность lst.insert(0, x) для list? | +O(n) | O(1) | O(log n) | O(n log n) || Все элементы сдвигаются; для очереди используют collections.deque. -->

### dict и set: хеш-таблицы

`dict` — хеш-таблица: ключ → `hash(key)` → индекс ячейки. Поиск, вставка, удаление — **O(1)** в среднем, O(n) в худшем (коллизии).

- С Python 3.7 dict **сохраняет порядок вставки** (гарантия языка).
- Ключ должен быть хешируемым: реализовать `__hash__` и `__eq__` согласованно.
- `set` — та же хеш-таблица без значений: `in` за O(1), операции `| & - ^`.

```python
counts = {}
for w in words:
    counts[w] = counts.get(w, 0) + 1
{**a, **b}, a | b        # слияние словарей (3.9+)
unique = set(items)
```

**На собесе:** как устроен dict? Что будет, если изменить объект-ключ после вставки? Почему list нельзя положить в set?

<!-- quiz: Какая средняя сложность поиска ключа в dict? | +O(1) | O(log n) | O(n) | O(n²) -->
<!-- quiz: Сохраняет ли dict порядок вставки ключей в Python 3.7+? | +Да, это гарантия языка | Нет, порядок случайный | Только для строковых ключей | Только при OrderedDict -->

### Копирование: поверхностное и глубокое

```python
import copy
a = [[1, 2], [3]]
b = a[:]              # или list(a), a.copy() — поверхностная копия
b[0].append(99)       # меняет и a[0]!
c = copy.deepcopy(a)  # полная рекурсивная копия
```

Поверхностная копия создаёт новый контейнер, но **с теми же вложенными объектами**.

<!-- quiz: Что копирует a[:] для вложенного списка a = [[1], [2]]? | +Только внешний список — вложенные объекты общие | Все уровни вложенности | Ничего, это ссылка на тот же список | Только вложенные списки -->

### Comprehensions

```python
squares = [x * x for x in range(10) if x % 2 == 0]
index = {name: i for i, name in enumerate(names)}
unique_lengths = {len(w) for w in words}
total = sum(x * x for x in range(10**6))   # генераторное выражение — без списка в памяти
```

Читаемость важнее краткости: вложенные comprehension с несколькими условиями лучше переписать циклом.

---

## Функции <!-- difficulty: 1 -->

Функции в Python — объекты первого класса: их можно передавать, возвращать и хранить в структурах.

### Аргументы: позиционные, именованные, *args, **kwargs

```python
def f(a, b=2, *args, c, d=4, **kwargs): ...
#     ^ позиц.  ^ лишние позиц.  ^ только именованные  ^ лишние именованные

def g(x, y, /, z, *, w): ...   # x, y — только позиционные; w — только именованный
g(1, 2, 3, w=4)

def call_with(*args, **kwargs):
    return target(*args, **kwargs)   # распаковка при вызове
```

**На собесе:** что такое `*args` и `**kwargs`? Как сделать аргумент только именованным?

### Ловушка: изменяемый аргумент по умолчанию

Значения по умолчанию вычисляются **один раз** — при определении функции.

```python
def add_item(item, items=[]):     # ПЛОХО
    items.append(item)
    return items
add_item(1); add_item(2)          # [1, 2] — список общий!

def add_item(item, items=None):   # ХОРОШО
    if items is None:
        items = []
    items.append(item)
    return items
```

Один из самых частых вопросов на junior-собеседованиях.

<!-- quiz: Почему def f(items=[]) — плохая практика? | +Список создаётся один раз при определении функции и общий для всех вызовов | Синтаксическая ошибка | Список пересоздаётся при каждом вызове и это медленно | Нельзя менять аргументы функции || Используйте items=None и создавайте список внутри. -->

### Области видимости: LEGB, global, nonlocal

Поиск имени: **L**ocal → **E**nclosing → **G**lobal → **B**uilt-in.

```python
counter = 0
def inc():
    global counter     # без global — UnboundLocalError
    counter += 1

def make_counter():
    count = 0
    def inc():
        nonlocal count  # изменяем переменную внешней функции
        count += 1
        return count
    return inc
```

<!-- quiz: В каком порядке Python ищет имя? | +Local → Enclosing → Global → Built-in | Global → Local → Built-in → Enclosing | Built-in → Global → Local | Local → Global → Enclosing → Built-in -->
<!-- quiz: Какое ключевое слово позволяет изменить переменную внешней (не глобальной) функции? | +nonlocal | global | outer | static -->

### Замыкания и lambda

**Замыкание** — функция, запомнившая переменные из внешней области видимости.

```python
def multiplier(n):
    return lambda x: x * n
double = multiplier(2)
double(5)  # 10

# Классическая ловушка: позднее связывание
funcs = [lambda: i for i in range(3)]
[f() for f in funcs]               # [2, 2, 2]
funcs = [lambda i=i: i for i in range(3)]   # [0, 1, 2]
```

`lambda` — анонимная функция из одного выражения; удобна для `key=` в `sorted`, `max`.

<!-- quiz: Что вернёт [f() for f in [lambda: i for i in range(3)]]? | +[2, 2, 2] | [0, 1, 2] | [0, 0, 0] | Ошибку || Позднее связывание: lambda читает i в момент вызова. -->

### Встроенные функции высшего порядка

```python
sorted(users, key=lambda u: (u.age, u.name), reverse=True)
list(map(str.upper, words)); list(filter(None, values))
any(x > 0 for x in xs), all(...), zip(a, b, strict=True), enumerate(items, start=1)
from functools import reduce, partial
```

---

## Декораторы <!-- difficulty: 2 -->

Декоратор — функция, принимающая функцию и возвращающая новую. `@decor` — синтаксический сахар для `f = decor(f)`.

### Как работает декоратор

```python
import time
from functools import wraps

def timer(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        try:
            return func(*args, **kwargs)
        finally:
            print(f"{func.__name__}: {time.perf_counter() - start:.3f}s")
    return wrapper

@timer
def work(): ...
```

`functools.wraps` копирует `__name__`, `__doc__`, `__wrapped__` — без него ломаются логи, документация и интроспекция.

**На собесе:** напиши декоратор, который считает время / кэширует результат / повторяет вызов при ошибке.

<!-- quiz: Зачем в декораторе использовать functools.wraps? | +Сохранить __name__, __doc__ и метаданные исходной функции | Ускорить вызов функции | Сделать функцию асинхронной | Кэшировать результат -->
<!-- quiz: Чему эквивалентна запись @decor над def f? | +f = decor(f) | f = f(decor) | decor = f(decor) | f.decor = True -->

### Декораторы с параметрами

Нужен ещё один уровень вложенности — «фабрика декораторов».

```python
def retry(times=3, exceptions=(Exception,)):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(1, times + 1):
                try:
                    return func(*args, **kwargs)
                except exceptions:
                    if attempt == times:
                        raise
        return wrapper
    return decorator

@retry(times=5)
def fetch(): ...
```

### Встроенные декораторы

- `@property` — метод как атрибут (геттер/сеттер с валидацией).
- `@staticmethod` — функция в пространстве имён класса, без `self`/`cls`.
- `@classmethod` — получает класс (`cls`); используется для альтернативных конструкторов.
- `@functools.lru_cache(maxsize=...)` / `@cache` — мемоизация.
- `@dataclass`, `@contextmanager`, `@abstractmethod`.

```python
class Date:
    @classmethod
    def from_string(cls, s):
        return cls(*map(int, s.split("-")))
```

<!-- quiz: Что получает первым аргументом метод с @classmethod? | +Класс (cls) | Экземпляр (self) | Ничего | Модуль -->

### Декораторы классов и порядок применения

```python
@a
@b
def f(): ...    # f = a(b(f)) — применяются снизу вверх
```

Декоратор может принимать и класс (как `@dataclass`), добавляя ему методы.

---

## ООП в Python <!-- difficulty: 2 -->

Четыре принципа: инкапсуляция, наследование, полиморфизм, абстракция. В Python — с поправкой на «мы все взрослые люди».

### Классы, экземпляры и атрибуты

```python
class Dog:
    species = "canis"           # атрибут класса — общий для всех
    def __init__(self, name):
        self.name = name        # атрибут экземпляра

d = Dog("Rex")
d.species = "wolf"   # создаёт атрибут экземпляра, класс не меняется
```

- `__init__` — инициализатор, `__new__` — конструктор (создаёт объект).
- Поиск атрибута: экземпляр → класс → родители по MRO.
- Ловушка: изменяемый атрибут класса (`items = []`) общий для всех экземпляров.

### Наследование, MRO и super()

```python
class A:
    def hello(self): return "A"
class B(A):
    def hello(self): return "B" + super().hello()
class C(A):
    def hello(self): return "C" + super().hello()
class D(B, C): pass

D().hello()   # "BCA"
D.__mro__     # D → B → C → A → object (алгоритм C3-линеаризации)
```

`super()` вызывает следующий класс **в MRO**, а не обязательно родителя. Это основа кооперативного множественного наследования и миксинов.

**На собесе:** что такое MRO? Ромбовидное наследование — как Python его решает?

<!-- quiz: Какой алгоритм Python использует для построения MRO? | +C3-линеаризацию | Поиск в ширину | Алфавитный порядок классов | Порядок импорта модулей -->
<!-- quiz: super() вызывает... | +следующий класс в MRO | всегда прямого родителя | object | метод с тем же именем в модуле -->

### Магические (dunder) методы

| Метод | Когда вызывается |
|---|---|
| `__repr__` / `__str__` | `repr(x)` (для разработчика) / `str(x)`, `print` |
| `__eq__`, `__lt__`, `__hash__` | сравнение, сортировка, ключи dict |
| `__len__`, `__getitem__`, `__iter__`, `__contains__` | протоколы коллекций |
| `__call__` | вызов объекта как функции |
| `__enter__` / `__exit__` | `with` |
| `__add__`, `__mul__`… | перегрузка операторов |

Если переопределили `__eq__`, а `__hash__` нет — объект становится нехешируемым.

<!-- quiz: Что произойдёт, если в классе определить __eq__, но не __hash__? | +Экземпляры станут нехешируемыми | Ничего не изменится | hash будет считаться по __eq__ | Ошибка при создании класса -->

### Инкапсуляция: _protected, __private, property

- `_name` — соглашение «внутреннее, не трогай».
- `__name` — **name mangling**: превращается в `_ClassName__name` (защита от конфликтов в наследниках, а не приватность).
- `@property` — контролируемый доступ без изменения интерфейса.

```python
class Account:
    def __init__(self, balance):
        self._balance = balance
    @property
    def balance(self):
        return self._balance
    @balance.setter
    def balance(self, value):
        if value < 0:
            raise ValueError("negative")
        self._balance = value
```

<!-- quiz: Во что превращается атрибут __secret в классе Account? | +_Account__secret | _secret | Account.secret | Он становится недоступным совсем || Это name mangling — защита от конфликтов имён, а не приватность. -->

### Абстракции: ABC, Protocol и утиная типизация

```python
from abc import ABC, abstractmethod
from typing import Protocol

class Storage(ABC):
    @abstractmethod
    def save(self, data: bytes) -> None: ...   # нельзя создать Storage()

class Closable(Protocol):          # структурная типизация (PEP 544)
    def close(self) -> None: ...

def shutdown(x: Closable): x.close()   # подойдёт любой объект с close()
```

ABC — номинальная проверка (нужно наследование), Protocol — структурная (достаточно методов).

### dataclasses, __slots__, NamedTuple

```python
from dataclasses import dataclass, field

@dataclass(frozen=True, slots=True)
class Point:
    x: float
    y: float
    tags: list[str] = field(default_factory=list)
```

- `@dataclass` генерирует `__init__`, `__repr__`, `__eq__`; `frozen=True` — неизменяемый и хешируемый.
- `__slots__` — фиксированный набор атрибутов: меньше памяти, быстрее доступ, нельзя добавить новый атрибут.
- `NamedTuple` — неизменяемый кортеж с именованными полями.

<!-- quiz: Что даёт @dataclass(frozen=True)? | +Неизменяемые экземпляры, которые можно хешировать | Быструю сериализацию в JSON | Автоматическую валидацию типов | Запрет наследования -->

### SOLID и композиция

- **S**ingle responsibility, **O**pen/closed, **L**iskov substitution, **I**nterface segregation, **D**ependency inversion.
- «Композиция предпочтительнее наследования»: объект *содержит* зависимость, а не *является* ею.
- Dependency Injection: передавайте зависимости через конструктор — это упрощает тестирование.

---

## Итераторы и генераторы <!-- difficulty: 2 -->

Ленивые вычисления — ключ к работе с большими данными без загрузки всего в память.

### Протокол итератора

- **Iterable** — объект с `__iter__()`, возвращающим итератор (list, dict, str, файл).
- **Iterator** — объект с `__next__()` (следующий элемент или `StopIteration`) и `__iter__()`, возвращающим self.

```python
it = iter([1, 2])
next(it), next(it)   # 1, 2
next(it)             # StopIteration
```

`for` под капотом: `iter()` + `next()` до `StopIteration`. Итератор **одноразовый**.

<!-- quiz: Какое исключение сигнализирует об окончании итератора? | +StopIteration | IndexError | EOFError | GeneratorExit -->

### Генераторы и yield

Функция с `yield` возвращает генератор — итератор, сохраняющий состояние между вызовами.

```python
def read_lines(path):
    with open(path) as f:
        for line in f:
            yield line.rstrip()

def fib():
    a, b = 0, 1
    while True:
        yield a
        a, b = b, a + b

from itertools import islice
list(islice(fib(), 10))
```

**На собесе:** чем генератор отличается от списка? Что вернёт `return` внутри генератора? Напиши генератор чтения файла чанками.

<!-- quiz: Главное преимущество генератора перед списком? | +Ленивость: элементы вычисляются по одному, без хранения всех в памяти | Генератор можно обойти много раз | Генератор поддерживает индексацию | Генераторы быстрее при случайном доступе -->

### yield from и генераторные выражения

```python
def flatten(items):
    for x in items:
        if isinstance(x, list):
            yield from flatten(x)   # делегирование вложенному генератору
        else:
            yield x

gen = (x * 2 for x in range(10**9))   # не создаёт миллиард элементов
```

### itertools и functools

```python
from itertools import chain, groupby, product, permutations, combinations, accumulate, count, cycle
list(chain([1], [2, 3]))
for key, group in groupby(sorted(words, key=len), key=len): ...
```

Пайплайны из генераторов: `read → filter → transform → batch` обрабатывают поток, держа в памяти по одному элементу.

---

## Исключения и контекстные менеджеры <!-- difficulty: 1 -->

### try / except / else / finally

```python
try:
    value = int(raw)
except ValueError as e:
    log.warning("bad input: %s", e)
    value = 0
else:
    print("без ошибок")          # выполняется, если исключения не было
finally:
    cleanup()                    # выполняется всегда
```

- Ловите **конкретные** исключения, не голый `except:` (он ловит даже `KeyboardInterrupt`).
- `raise ... from e` — сохраняет цепочку причин.
- EAFP («проще попросить прощения») — питоничный стиль вместо множества `if`.

<!-- quiz: Когда выполняется блок else в try/except/else? | +Если в try не было исключения | Всегда | Только при исключении | Если сработал finally -->

### Иерархия исключений и свои исключения

`BaseException` → `Exception` → (`ValueError`, `TypeError`, `KeyError`, `OSError`…). `SystemExit`, `KeyboardInterrupt` — наследники `BaseException`, но не `Exception`.

```python
class AppError(Exception):
    """Базовое исключение приложения."""
class NotFoundError(AppError):
    def __init__(self, entity, id_):
        super().__init__(f"{entity} {id_} not found")
```

С 3.11: `ExceptionGroup` и `except*` для групп ошибок (например, из `asyncio.TaskGroup`).

### Контекстные менеджеры: with

Гарантируют освобождение ресурса (файл, соединение, блокировка) даже при исключении.

```python
class Timer:
    def __enter__(self):
        self.start = time.perf_counter()
        return self
    def __exit__(self, exc_type, exc, tb):
        self.elapsed = time.perf_counter() - self.start
        return False     # True подавит исключение

from contextlib import contextmanager
@contextmanager
def transaction(conn):
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
```

<!-- quiz: Какие методы реализует контекстный менеджер? | +__enter__ и __exit__ | __init__ и __del__ | __open__ и __close__ | __start__ и __stop__ -->

---

## Модули, пакеты и инструменты <!-- difficulty: 1 -->

### Импорты, пакеты и __name__

- Модуль — файл `.py`, пакет — каталог с модулями (`__init__.py` выполняется при импорте пакета).
- Модуль выполняется **один раз** при первом импорте и кэшируется в `sys.modules`.
- `if __name__ == "__main__":` — код запускается только при прямом запуске файла.
- Циклические импорты лечатся переносом импорта внутрь функции или рефакторингом зависимостей.

### Виртуальные окружения и зависимости

```bash
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
poetry add fastapi       # или uv add fastapi — быстрый современный менеджер
```

Зачем: изоляция версий зависимостей между проектами. Фиксируйте версии (lock-файлы) для воспроизводимых сборок.

<!-- quiz: Зачем нужно виртуальное окружение? | +Изолировать зависимости проекта от других проектов и системы | Ускорить интерпретатор | Скомпилировать проект в exe | Запускать код в браузере -->

### Стиль кода и качество

- **PEP 8** — стиль: snake_case для функций, PascalCase для классов, 4 пробела.
- **PEP 257** — docstrings.
- Инструменты: `ruff` (линтер + форматтер), `black`, `isort`, `mypy`, `pre-commit`.
- Zen of Python: `import this` — «явное лучше неявного», «простое лучше сложного».

### Git для разработчика

```bash
git switch -c feature/login
git add -p && git commit -m "feat: login endpoint"
git rebase main          # или merge — знать разницу
git stash, git cherry-pick, git reset --soft HEAD~1, git log --oneline --graph
```

**На собесе:** merge vs rebase? Как откатить коммит, который уже запушен (→ `git revert`)? Что такое конфликт и как его решать?

<!-- quiz: Как безопасно отменить уже запушенный коммит? | +git revert — новый коммит, отменяющий изменения | git reset --hard и force push | Удалить ветку | git stash -->

---

## Типизация <!-- difficulty: 2 -->

Аннотации не влияют на выполнение, но ловят ошибки статически и служат документацией.

### Аннотации и mypy

```python
def greet(name: str, times: int = 1) -> list[str]:
    return [f"Hi, {name}"] * times

user: dict[str, int | None] = {}
from typing import Optional, Any, Callable, Iterable
handler: Callable[[int, str], bool]
```

`mypy` / `pyright` проверяют типы без запуска. Pydantic и FastAPI используют аннотации в рантайме для валидации.

### Generics, TypeVar и Protocol

```python
from typing import TypeVar, Generic

T = TypeVar("T")
def first(items: list[T]) -> T:
    return items[0]

class Repository(Generic[T]):
    def get(self, id: int) -> T | None: ...

# 3.12+: def first[T](items: list[T]) -> T: ...
```

- `TypedDict` — типизированный словарь, `Literal["a", "b"]` — конкретные значения, `Final` — константа.

### Pydantic: валидация данных <!-- optional -->

```python
from pydantic import BaseModel, Field, EmailStr

class User(BaseModel):
    id: int
    email: EmailStr
    age: int = Field(ge=0, le=150)

User.model_validate({"id": "1", "email": "a@b.c", "age": 30})  # "1" → 1
```

Используется в FastAPI, настройках (`pydantic-settings`), парсинге ответов LLM.

---

## Память и производительность <!-- difficulty: 3 -->

### Управление памятью: подсчёт ссылок и GC

- Основной механизм — **подсчёт ссылок**: объект удаляется, когда счётчик падает до 0 (`sys.getrefcount`).
- **Циклический сборщик мусора** (`gc`) находит циклы ссылок (a → b → a). Поколения 0/1/2.
- `weakref` — ссылка, не увеличивающая счётчик (кэши, обратные ссылки).
- Память под мелкие объекты выделяется пулами (pymalloc) и не всегда возвращается ОС.

**На собесе:** как Python освобождает память? Что такое утечка памяти в Python и как её найти (`tracemalloc`)?

<!-- quiz: Зачем в CPython нужен циклический сборщик мусора, если есть подсчёт ссылок? | +Подсчёт ссылок не освобождает объекты, ссылающиеся друг на друга по кругу | Подсчёт ссылок работает только для int | Чтобы сжимать память | Он нужен только в PyPy -->

### GIL

**Global Interpreter Lock** — мьютекс CPython: в один момент байткод исполняет только один поток.

- CPU-bound задачи потоки **не ускоряют** → `multiprocessing` / C-расширения / NumPy.
- I/O-bound задачи потоки ускоряют: GIL отпускается на время ввода-вывода.
- Python 3.13 — экспериментальная сборка **free-threaded** (без GIL, PEP 703).

**На собесе:** что такое GIL и зачем он нужен (простота подсчёта ссылок, безопасность C-расширений)?

<!-- quiz: Что ускорят потоки (threading) в CPython с GIL? | +I/O-bound задачи: сеть, диск | CPU-bound вычисления | Ничего | Только операции с NumPy -->

### Профилирование и оптимизация

```bash
python -m cProfile -s cumtime app.py
python -m timeit "sum(range(1000))"
```

- Сначала **измерь** (cProfile, py-spy, line_profiler), потом оптимизируй.
- Правильная структура данных (set вместо list для `in`) даёт больше, чем микрооптимизации.
- Встроенные функции и comprehension быстрее ручных циклов; `__slots__` экономит память.
- Тяжёлые вычисления — NumPy, Cython, Rust (PyO3), multiprocessing.

---

## Конкурентность и asyncio <!-- difficulty: 3 -->

### Потоки, процессы, корутины: что выбрать

| Подход | Подходит для | Ограничения |
|---|---|---|
| `threading` | I/O-bound, блокирующие библиотеки | GIL, гонки данных |
| `multiprocessing` | CPU-bound | дорого создавать, данные сериализуются (pickle) |
| `asyncio` | много одновременных I/O (сеть) | нужны async-библиотеки, один поток |

`concurrent.futures.ThreadPoolExecutor` / `ProcessPoolExecutor` — единый простой интерфейс пулов.

<!-- quiz: Что лучше выбрать для CPU-bound задачи в CPython? | +multiprocessing / ProcessPoolExecutor | threading | asyncio | time.sleep -->

### asyncio: event loop, корутины, await

```python
import asyncio

async def fetch(session, url):
    async with session.get(url) as resp:
        return await resp.text()

async def main(urls):
    async with aiohttp.ClientSession() as s:
        results = await asyncio.gather(*(fetch(s, u) for u in urls))

asyncio.run(main(urls))
```

- Корутина приостанавливается на `await`, отдавая управление **event loop**.
- **Кооперативная многозадачность**: блокирующий вызов (`time.sleep`, `requests`) блокирует весь цикл → `asyncio.to_thread`.
- `asyncio.TaskGroup` (3.11+) — структурная конкурентность; `asyncio.Semaphore` — ограничение параллелизма; `asyncio.wait_for` — таймауты.

**На собесе:** чем корутина отличается от потока? Что будет, если вызвать `time.sleep` в async-функции?

<!-- quiz: Что будет, если вызвать time.sleep(5) внутри async-функции? | +Заблокируется весь event loop на 5 секунд | Приостановится только эта корутина | Python выбросит ошибку | Ничего, sleep автоматически станет асинхронным || Используйте await asyncio.sleep() или asyncio.to_thread. -->

### Синхронизация и гонки данных

```python
import threading
lock = threading.Lock()
with lock:
    counter += 1     # += не атомарен даже с GIL
```

- `Lock`, `RLock`, `Semaphore`, `Event`, `Condition`; `queue.Queue` — потокобезопасная очередь (producer/consumer).
- Deadlock — взаимная блокировка; лечится единым порядком захвата блокировок и таймаутами.

---

## Тестирование <!-- difficulty: 2 -->

### pytest: тесты, фикстуры, параметризация

```python
import pytest

@pytest.fixture
def user():
    return User(name="Ann")

@pytest.mark.parametrize("a, b, expected", [(1, 2, 3), (0, 0, 0)])
def test_add(a, b, expected):
    assert add(a, b) == expected

def test_raises():
    with pytest.raises(ValueError):
        parse("bad")
```

Фикстуры с `yield` делают setup/teardown; области видимости: function, module, session.

<!-- quiz: Какой декоратор pytest запускает тест с разными наборами данных? | +@pytest.mark.parametrize | @pytest.fixture | @pytest.repeat | @pytest.dataset -->

### Моки и изоляция

```python
from unittest.mock import patch, MagicMock

@patch("app.services.requests.get")
def test_fetch(mock_get):
    mock_get.return_value.json.return_value = {"ok": True}
    assert fetch_status() is True
    mock_get.assert_called_once()
```

Патчить нужно там, где объект **используется**, а не где определён.

<!-- quiz: Где нужно патчить объект с помощью unittest.mock.patch? | +Там, где он используется (импортирован) | Там, где он определён | В conftest.py | В __init__.py пакета -->

### Пирамида тестов, покрытие, TDD

- Пирамида: много unit → меньше интеграционных → мало e2e.
- `pytest-cov` — покрытие; 100% не гарантирует отсутствие багов.
- TDD: red → green → refactor.
- Хороший тест: быстрый, изолированный, детерминированный, проверяет поведение, а не реализацию.

---

## Алгоритмы для собеседования <!-- difficulty: 2 -->

Live-coding на junior/middle: задачи уровня LeetCode Easy/Medium.

### Big O и сложность

- O(1) < O(log n) < O(n) < O(n log n) < O(n²) < O(2ⁿ).
- Оцениваются время и дополнительная память; константы и младшие члены отбрасываются.
- Вложенный цикл по одному массиву — обычно O(n²); замена внутреннего поиска на set/dict даёт O(n).

<!-- quiz: Какая сложность у поиска элемента x in some_set? | +O(1) в среднем | O(n) | O(log n) | O(n²) -->

### collections и heapq

```python
from collections import Counter, defaultdict, deque, OrderedDict
Counter("abracadabra").most_common(2)     # [('a', 5), ('b', 2)]
graph = defaultdict(list); graph[u].append(v)
q = deque(); q.append(x); q.popleft()     # O(1) с обоих концов
import heapq
heapq.nsmallest(3, nums); heapq.heappush(h, (priority, item))
```

<!-- quiz: Какая структура даёт O(1) добавление и удаление с обоих концов? | +collections.deque | list | tuple | dict -->

### Типовые паттерны задач

- **Хеш-таблица**: two sum, анаграммы, подсчёт частот.
- **Два указателя**: палиндромы, слияние отсортированных массивов.
- **Скользящее окно**: подстрока без повторов, максимальная сумма k элементов.
- **BFS/DFS**: обход графа/дерева, острова в матрице.
- **Бинарный поиск**: `bisect`, поиск по ответу.

```python
def two_sum(nums, target):
    seen = {}
    for i, x in enumerate(nums):
        if target - x in seen:
            return seen[target - x], i
        seen[x] = i
```

### Как вести себя на live-coding

1. Уточни условие и граничные случаи (пустой ввод, дубликаты, отрицательные числа).
2. Проговори наивное решение и его сложность.
3. Улучши, напиши чистый код, прогони руками на примере.
4. Назови итоговую сложность по времени и памяти.

---

## Метапрограммирование <!-- difficulty: 3, optional -->

Продвинутая тема: встречается на middle+ собеседованиях и в коде фреймворков (Django ORM, SQLAlchemy, Pydantic).

### Дескрипторы

Объект с `__get__` / `__set__` / `__delete__`, лежащий в атрибуте класса. На дескрипторах построены `property`, методы, `classmethod`.

```python
class Positive:
    def __set_name__(self, owner, name):
        self.name = "_" + name
    def __get__(self, obj, objtype=None):
        return getattr(obj, self.name)
    def __set__(self, obj, value):
        if value <= 0:
            raise ValueError("must be positive")
        setattr(obj, self.name, value)

class Order:
    qty = Positive()
```

<!-- quiz: На каком механизме построены property, classmethod и обычные методы? | +Дескрипторы | Метаклассы | Декораторы классов | Генераторы -->

### Метаклассы

Класс класса: `type` — метакласс по умолчанию. `class A: ...` ≈ `A = type("A", (), {...})`.

```python
class Registry(type):
    classes = {}
    def __new__(mcs, name, bases, ns):
        cls = super().__new__(mcs, name, bases, ns)
        mcs.classes[name] = cls
        return cls
```

Чаще достаточно `__init_subclass__` или декоратора класса — метакласс нужен редко.

### __getattr__, __getattribute__, __new__

- `__getattribute__` — вызывается при **любом** доступе к атрибуту.
- `__getattr__` — только если атрибут не найден обычным путём (прокси, ленивые атрибуты).
- `__new__` — создаёт экземпляр (синглтоны, наследование от неизменяемых типов).

```python
class Singleton:
    _instance = None
    def __new__(cls, *a, **kw):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
```
