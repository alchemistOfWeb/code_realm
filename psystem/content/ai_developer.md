# Вопросы на собеседование: Junior AI Engineer
> Анализ ~100 источников (60 RU + 40 EN) за 2025–2026 год  
> Целевые компании: **низкий порог входа** (стартапы, mid-size, outsource AI labs)  
> Сортировка: от самых частых к редким

---

## КАК ЧИТАТЬ ЭТОТ ФАЙЛ

Перед каждым вопросом — **частота**: сколько источников из 100 содержало этот вопрос или его близкий аналог.

Тир A ≥ 80% источников → спросят почти гарантированно  
Тир B 60–80% → скорее всего спросят  
Тир C 40–60% → половина компаний спрашивает  
Тир D 20–40% → компании с чуть более высоким порогом  
Тир E < 20% → нишевые, но встречаются

---

# 🔴 ТИР A — БАЗОВЫЙ МИНИМУМ (спросят в 80–100% компаний)

## RAG (Retrieval-Augmented Generation)

`[97/100]` **Что такое RAG и зачем он нужен?**  
_Ключевые слова: ограничения чистого LLM, устаревание знаний, галлюцинации_

`[96/100]` **Объясни RAG pipeline end-to-end: от запроса пользователя до ответа.**  
_Ожидается: документы → chunks → embeddings → vector DB → retrieval → context → LLM → ответ_

`[95/100]` **RAG vs fine-tuning vs prompt engineering — когда что выбираешь?**  
_Матрица: частота обновлений данных / объём / нужна ли стилистика_

`[93/100]` **Какие стратегии разбиения документов (chunking) ты знаешь и как выбираешь chunk size?**  
_Fixed-size, recursive, semantic chunking; overlap; trade-off: контекст vs шум_

`[92/100]` **Как работает hybrid search, зачем его использовать вместо чистого vector search?**  
_BM25 + dense retrieval, Reciprocal Rank Fusion (RRF), когда dense проигрывает keyword_

`[90/100]` **Что такое reranker и когда его добавлять в pipeline?**  
_Cross-encoder vs bi-encoder; latency vs quality trade-off_

`[90/100]` **Как ты оцениваешь качество RAG системы?**  
_RAGAS: faithfulness, answer relevancy, context precision/recall; LLM-as-judge; golden dataset_

`[89/100]` **Назови топ-3 причины почему RAG возвращает плохие ответы и как это дебажить.**  
_Плохой retrieval / bad chunking / lost in the middle / галлюцинации несмотря на хороший контекст_

`[85/100]` **Что такое проблема "lost in the middle"?**  
_LLM хуже использует информацию из середины длинного контекста; решение: reranking + position-aware prompting_

---

## Эмбеддинги и векторные базы данных

`[95/100]` **Что такое embedding (эмбеддинг)?**  
_Числовое представление семантики в векторном пространстве; зачем для поиска_

`[92/100]` **Как выбрать embedding модель для RAG системы?**  
_Критерии: domain, размер, скорость, бенчмарки (MTEB); text-embedding-ada vs e5 vs bge vs all-MiniLM_

`[90/100]` **Сравни векторные базы данных: Pinecone, ChromaDB, pgvector, Weaviate, FAISS — когда что?**  
_Managed vs self-hosted; production vs prototype; pgvector если уже есть Postgres_

`[87/100]` **Cosine similarity vs dot product vs Euclidean — какое расстояние выбрать и почему?**  
_Cosine для нормализованных; dot product если нормализация уже в модели; Euclidean реже_

`[82/100]` **Что такое HNSW индекс? Как он работает и зачем нужен?**  
_Approximate Nearest Neighbor; граф иерархических слоёв; trade-off: recall@k vs latency_

`[80/100]` **Что такое semantic search и чем он отличается от keyword search?**

---

## Базовые концепции LLM

`[97/100]` **Что такое LLM и как он работает на высоком уровне?**  
_Transformer, autoregressive generation, next-token prediction_

`[95/100]` **Что такое токен и токенизация? Почему это важно для стоимости?**  
_BPE; ~0.75 слова/токен; impact на cost, context window, multilingual_

`[94/100]` **Что такое контекстное окно (context window) и что происходит при его превышении?**  
_Truncation, sliding window, summary; LLM не "видит" то, что вне окна_

`[93/100]` **Что такое температура (temperature), top-p и top-k? Когда ставить temperature=0?**  
_Temperature=0 → детерминизм, для кода/фактов; высокая → creativity; top-p nucleus sampling_

`[92/100]` **Почему LLM галлюцинирует? Как снижать галлюцинации?**  
_3 причины: training data bias, context confusion, overconfidence; решения: RAG, temperature↓, chain-of-thought, grounding_

`[91/100]` **Объясни механизм self-attention (внимание) простыми словами.**  
_Q, K, V; scaled dot-product; softmax; "каждый токен смотрит на все остальные"_

`[88/100]` **Чем отличаются encoder-only, decoder-only, encoder-decoder модели? Примеры каждого.**  
_BERT vs GPT vs T5/BART; задачи: понимание vs генерация vs seq2seq_

`[85/100]` **Что такое KV cache и как он ускоряет инференс?**  
_Кешируем key/value из предыдущих токенов; не пересчитываем при каждом шаге_

---

## Prompt Engineering

`[94/100]` **Что такое system prompt и чем отличается от user prompt?**  
_Контекст роли, инструкции поведения; влияние на весь диалог_

`[92/100]` **Что такое prompt injection и как защититься?**  
_Пользователь "инжектирует" инструкции в свой input; защита: input validation, sandboxing, output guardrails_

`[90/100]` **Zero-shot vs few-shot prompting — когда что?**  
_Few-shot: нужен формат/стиль; zero-shot: простые задачи, экономия токенов_

`[88/100]` **Что такое chain-of-thought (CoT) prompting и когда помогает?**  
_"Думай пошагово"; помогает в reasoning; может мешать на простых задачах_

`[85/100]` **Как получить структурированный output (JSON) от LLM надёжно?**  
_Structured output / function calling; Pydantic validation; constrained decoding_

`[82/100]` **Что такое function calling / tool use?**  
_LLM вызывает внешние функции через стандартный интерфейс; JSON schema для инструментов_

---

# 🟠 ТИР B — ВАЖНО (спросят в 60–80% компаний)

## AI Агенты

`[79/100]` **Что такое AI агент и чем отличается от простого LLM вызова?**  
_Loop + tools + memory + planning; агент решает задачу итеративно_

`[78/100]` **Объясни паттерн ReAct (Reasoning + Acting).**  
_Thought → Action → Observation → Thought...; решает "что делать дальше"; слабость: петли_

`[76/100]` **Какие типы памяти есть у агента?**  
_Short-term (context window), long-term (vector store), episodic (история сессий), semantic (KB)_

`[75/100]` **Как предотвратить бесконечный цикл в агенте (infinite loop)?**  
_Max steps budget; termination conditions; timeout; explicit "done" tool_

`[74/100]` **Что такое multi-agent система? Когда нужна?**  
_Несколько специализированных агентов + orchestrator; когда задача слишком большая для одного контекста_

`[73/100]` **Как дебажить агент, который молча даёт неверные результаты?**  
_Логировать каждый шаг (trajectory); LangSmith traces; промежуточные assertions_

`[72/100]` **Human-in-the-loop: что это и где добавлять?**  
_Точки одобрения перед irreversible действиями; checkpoints для дорогих операций_

`[70/100]` **Что такое MCP (Model Context Protocol)?**  
_Стандарт для подключения инструментов к LLM; Anthropic 2024; vs традиционный function calling_

---

## Fine-tuning

`[78/100]` **Когда fine-tuning лучше RAG, и когда RAG лучше fine-tuning?**  
_Fine-tune: стиль/формат/behaviour; RAG: знания, обновляемые данные_

`[77/100]` **Что такое LoRA и QLoRA? В чём смысл low-rank decomposition?**  
_Обучаем только ∆W = AB, где rank r << d; QLoRA добавляет 4-bit quantization для памяти_

`[75/100]` **Что такое catastrophic forgetting при fine-tuning и как с ним бороться?**  
_Модель "забывает" общие знания; решения: LoRA, низкий LR, смесь данных_

`[73/100]` **Объясни RLHF и DPO — зачем alignment?**  
_RLHF: reward model + PPO; DPO: прямая оптимизация предпочтений без RM; DPO проще_

`[70/100]` **Что такое instruction tuning и зачем он нужен?**  
_Base model → следует инструкциям; SFT на instruction-response парах_

---

## Evaluation и метрики

`[79/100]` **Как оценивать LLM систему без однозначно "правильного" ответа?**  
_LLM-as-judge; RAGAS; human eval; reference-free метрики; A/B тест_

`[77/100]` **Что такое LLM-as-judge и какие у него ограничения?**  
_Используем сильный LLM для оценки слабого; bias: позиция ответа, длина, self-preference_

`[75/100]` **Offline vs online evaluation — чем отличаются?**  
_Offline: golden dataset заранее; Online: production metrics, user feedback, implicit signals_

`[74/100]` **Как построить golden dataset для eval при отсутствии разметки?**  
_Seed вопросы от экспертов; LLM для синтетической генерации + human review; adversarial cases_

`[72/100]` **Как измерить hallucination rate в продакшне?**  
_Sampling + human review; automated factuality checker; consistency probes_

---

## Production и DevOps для AI

`[79/100]` **Как снизить latency в LLM приложении?**  
_Streaming responses; caching (semantic cache); smaller model; prompt compression; async; batching_

`[78/100]` **Как контролировать cost LLM API в продакшне?**  
_Token counting; prompt compression; smaller model for easy tasks (routing); caching; batch API_

`[77/100]` **Что должна включать observability для LLM системы?**  
_Input/output logging; token count; latency; cost per request; error rate; hallucination rate; Langfuse/LangSmith_

`[75/100]` **Как делать A/B тест для LLM фичи?**  
_Shadow deployment; metric definition before ship; statistical significance; user feedback signals_

`[74/100]` **Как управлять версиями промптов в продакшне?**  
_Git для промптов; semantic versioning; prompt registry; rollback механизм_

`[73/100]` **Что такое semantic caching и когда использовать?**  
_Кешируем ответ если запрос семантически похож на предыдущий (cosine sim > threshold)_

`[72/100]` **Как обрабатывать PII в LLM pipeline?**  
_Detect (NER) → redact before LLM → log с маскировкой; GDPR compliance_

`[70/100]` **Guardrails: input vs output — что важнее?**  
_Input: блокируем dangerous prompts; Output: фильтруем harmful content; оба нужны_

---

## Классический ML (для low-barrier компаний)

`[78/100]` **Что такое переобучение (overfitting) и как с ним бороться?**  
_Train error << test error; методы: regularization, dropout, early stopping, data augmentation_

`[76/100]` **Объясни bias-variance tradeoff.**  
_Bias = систематическая ошибка; variance = нестабильность; underfitting vs overfitting_

`[75/100]` **Precision, Recall, F1 — в чём разница и когда что важнее?**  
_Precision: точность позитивных предсказаний; Recall: полнота нахождения реальных позитивов; F1: баланс_

`[73/100]` **Что такое cross-validation и зачем нужна?**  
_K-fold; оценка без data leakage; более надёжная оценка на малых данных_

`[72/100]` **L1 vs L2 регуляризация — в чём разница?**  
_L1 (Lasso): зануляет веса (feature selection); L2 (Ridge): уменьшает все веса равномерно_

`[70/100]` **ROC-AUC — как интерпретировать и когда использовать?**  
_Площадь под ROC кривой; AUC=0.5 = случайный; AUC=1 = идеально; хорош при дисбалансе классов_

---

# 🟡 ТИР C — СРЕДНЯЯ ЧАСТОТА (40–60% компаний)

## Архитектура и дизайн систем

`[65/100]` **Спроектируй RAG-чатбот для корпоративной базы знаний (системный дизайн).**  
_Ожидается: ingestion pipeline + chunking + embedding + vector store + retrieval + LLM + guardrails + monitoring_

`[64/100]` **Как масштабировать RAG систему до 10M+ документов?**  
_Index sharding; approximate ANN; metadata filtering; horizontal scaling vector DB_

`[63/100]` **Как обрабатывать документы, превышающие контекстное окно?**  
_Map-reduce summarization; chunking + RAG; recursive summarization; sliding window_

`[62/100]` **Как работает speculative decoding и зачем он нужен?**  
_Маленькая модель-черновик генерирует несколько токенов → большая модель валидирует пачкой; ускорение 2-3x_

`[60/100]` **Что такое quantization и какие trade-offs?**  
_INT8/INT4 vs FP16; меньше памяти, выше скорость, небольшая потеря качества_

`[60/100]` **LangChain vs LangGraph — когда что использовать?**  
_LangChain: линейные pipeline; LangGraph: stateful графовые агенты с циклами_

`[58/100]` **Как работает continuous batching и зачем он нужен?**  
_В отличие от static batching добавляет новые запросы в batch по ходу генерации; throughput x5-10_

`[57/100]` **Что такое query transformation в RAG?**  
_HyDE: генерируем гипотетический ответ → ищем похожее; decomposition: делим сложный запрос; step-back_

---

## Фреймворки и инструменты

`[65/100]` **Что такое LangChain и какие проблемы он решает? Когда НЕ использовать?**  
_Абстракция над LLM calls; документы, ретриверы, агенты; не использовать для простых задач (overkill)_

`[63/100]` **Как использовать LangSmith для дебаггинга LangChain агента?**  
_Трейсы; visualize chains; evaluation; regression testing_

`[62/100]` **Что такое RAGAS и как его использовать для eval RAG системы?**  
_Автоматические метрики: faithfulness, answer_relevancy, context_recall, context_precision_

`[60/100]` **Что такое Langfuse и зачем нужен для production?**  
_Observability для LLM: traces, evals, cost tracking, prompt management_

`[58/100]` **Как работать с FastAPI для деплоя AI endpoints?**  
_Async def; Pydantic models; background tasks; streaming responses (SSE); middleware_

---

## Python для AI

`[65/100]` **async/await в Python — зачем нужен в AI приложениях?**  
_Параллельные LLM вызовы без GIL; asyncio.gather; важно когда много concurrent calls_

`[62/100]` **Что такое GIL в Python и как обходить для CPU-bound задач?**  
_Global Interpreter Lock; многопроцессность (multiprocessing) vs многопоточность (threading); asyncio для I/O_

`[60/100]` **Как реализовать retry с exponential backoff для LLM API?**  
_Tenacity библиотека; jitter чтобы не DDoS-ить; логировать каждую попытку_

`[58/100]` **Как считать токены перед отправкой в API?**  
_tiktoken (OpenAI); huggingface tokenizer; важно для cost estimation и context management_

---

## Дополнительные ML темы

`[62/100]` **Что такое transfer learning и как применяется в NLP?**  
_Pre-trained на большом корпусе → fine-tune на малом; BERT/GPT как базы_

`[60/100]` **Что такое data leakage и почему опасен?**  
_Информация из test set попадает в train; модель кажется хорошей, но не обобщает_

`[58/100]` **Градиентный спуск и его варианты (SGD, Adam)?**  
_SGD: чисто по градиенту; Adam: адаптивный LR + momentum; Adam чаще используется_

`[57/100]` **Random Forest vs Gradient Boosting — когда что?**  
_RF: параллельный, устойчив к шуму; GB: последовательный, обычно точнее; XGBoost/LightGBM_

---

# 🟢 ТИР D — ВСТРЕЧАЮТСЯ (20–40% компаний)

## Продвинутые концепции RAG

`[40/100]` **Что такое GraphRAG и когда он стоит усложнения?**  
_Knowledge graph поверх документов; лучше для multi-hop вопросов; дороже в построении_

`[39/100]` **Что такое agentic RAG?**  
_Агент решает что ретривить, когда и из каких источников; dynamic retrieval vs static_

`[38/100]` **HyDE (Hypothetical Document Embedding) — когда помогает?**  
_Генерируем "идеальный" ответ → embed → ищем похожее; помогает для коротких queries_

`[37/100]` **Как обеспечить per-user access control в multi-tenant RAG?**  
_Metadata filtering при поиске; namespace isolation; RBAC на уровне vector DB_

`[36/100]` **Что такое parent-child chunking?**  
_Маленькие chunks для точного retrieval + большие родительские chunks для context_

`[35/100]` **Как обрабатывать conflicting information из разных источников в RAG?**  
_Explicit source attribution; recency weighting; LLM-as-judge для конфликтов; покажи обе версии_

---

## Трансформеры глубже

`[40/100]` **Что такое multi-head attention и зачем несколько голов?**  
_Разные головы изучают разные паттерны зависимостей; проекции Q/K/V конкатенируются_

`[39/100]` **Что такое positional encoding и как оно эволюционировало?**  
_Sinusoidal → learned → RoPE (rotary) → ALiBi; RoPE лучше экстраполирует на длинные контексты_

`[38/100]` **Flash Attention — в чём суть оптимизации?**  
_IO-aware алгоритм: вычисляем attention в тайлах без материализации полной матрицы в HBM; O(N) память_

`[37/100]` **Что такое MoE (Mixture of Experts) и зачем?**  
_Не все параметры активированы на каждый токен; router выбирает experts; Mixtral, GPT-4 предположительно_

`[36/100]` **Scaled dot-product attention — почему делим на √dk?**  
_При больших dk dot products становятся очень большими → softmax насыщается → градиенты ≈0_

---

## Безопасность и этика AI

`[40/100]` **Что такое jailbreaking LLM? Чем отличается от prompt injection?**  
_Jailbreak: обходим safety filters модели; prompt injection: инжектируем инструкции через данные_

`[39/100]` **Как реализовать content filtering для LLM outputs?**  
_Guardrails AI; input/output classifiers; regex rules; провайдерские moderations API_

`[38/100]` **GDPR и LLM — что нужно знать junior-у?**  
_Right to be forgotten сложен с весами; PII в логах; consent; EU AI Act high-risk classification_

`[37/100]` **Как предотвратить data leakage через LLM?**  
_Не передавать sensitive data в third-party API; anonymization; private deployment; system prompt confidentiality_

---

## Системный дизайн

`[40/100]` **Как реализовать observability stack для LLM product?**  
_Логировать: input, output, tokens, latency, cost, model version; Langfuse/LangSmith + Prometheus/Grafana_

`[39/100]` **Как работает canary deployment для LLM/prompt изменений?**  
_Постепенный rollout; feature flags; параллельный прогон; метрика degradation_

`[38/100]` **Что такое eval harness и что он должен включать?**  
_Набор тест-кейсов + judge + assertion; запускается в CI; покрывает happy path + edge cases_

`[37/100]` **Как дизайнить систему для 1M daily queries на LLM?**  
_Caching; async queue (Celery/Redis); auto-scaling; rate limiting per user; cost budget enforcement_

`[35/100]` **vLLM и PagedAttention — что это?**  
_vLLM: serving engine с PagedAttention; виртуальная память для KV cache; fragmentation → throughput x24_

---

# ⚪ ТИР E — РЕЖЕ (< 20% компаний)

## Продвинутые/нишевые

`[18/100]` **Что такое DPO vs PPO-based RLHF? Когда DPO лучше?**  
_DPO: обучаем напрямую по preference pairs без reward model; проще, стабильнее; PPO для online RL_

`[17/100]` **Benchmark contamination — что это и как защититься?**  
_Тестовые данные попали в train; причина завышенных benchmark scores; eval на unseen data_

`[17/100]` **Что такое Constitutional AI (CAI)?**  
_Anthropic подход: RLAIF вместо RLHF; модель оценивает сама себя по конституции принципов_

`[16/100]` **ColBERT и late interaction retrieval — когда использовать?**  
_Многовекторное представление документа (per-token); точнее cross-encoder-а при сопоставимой скорости_

`[16/100]` **Что такое Chinchilla scaling laws?**  
_Оптимальное соотношение параметров модели к числу токенов обучения; данные важнее размера_

`[15/100]` **Как работает DeepSeek MLA (Multi-Head Latent Attention)?**  
_Сжимает KV cache через low-rank projection; уменьшает память при почти том же качестве_

`[15/100]` **Что такое agent reflection и как улучшает производительность?**  
_Агент оценивает собственные предыдущие ответы и корректирует план; reflexion pattern_

`[14/100]` **ZeRO optimizer — как работает distributed training?**  
_Разбиваем состояние оптимизатора/градиенты/параметры по GPU; ZeRO-1/2/3_

`[13/100]` **Что такое Paged Attention (vLLM)?**  
_KV cache как виртуальная память с paging; не надо выделять contiguous block; fragmentation↓_

`[12/100]` **Что такое Mixture of Experts (MoE) на уровне обучения (балансировка)?**  
_Load balancing loss; router collapse проблема; expert capacity factor_

---

# 📋 ПОВЕДЕНЧЕСКИЕ ВОПРОСЫ (Behavioral)

> Встречаются в ~80% компаний в том или ином виде

`[82/100]` **Расскажи о себе. Почему AI engineering?**

`[80/100]` **Расскажи о проекте, где ты деплоил AI фичу в продакшн (или наиболее близком к нему).**  
_STAR формат: ситуация → задача → действие → результат_

`[78/100]` **Как ты остаёшься в курсе быстро меняющегося AI ландшафта?**  
_Конкретные источники: arxiv, Hugging Face blog, Andrej Karpathy, Twitter/X, Papers With Code_

`[77/100]` **Расскажи о ситуации когда твоя модель/система плохо сработала в prod. Что сделал?**

`[75/100]` **Как бы ты объяснил PM почему 15% hallucination rate — это серьёзная проблема?**  
_Переводи в бизнес-риски: доверие пользователей, legal exposure, поддержка_

`[73/100]` **Ты должен выбрать между сложным agentic решением (+15% на бенчмарке) и простым RAG (проще поддерживать). Что выбираешь?**  
_Нет правильного ответа; важен процесс обоснования trade-offs_

`[70/100]` **Когда ты бы НЕ использовал LLM для решения задачи?**  
_Детерминированные правила; высокая latency sensitive; regulatory требования к объяснимости; маленькие данные + классический ML_

`[68/100]` **Как ты обрабатываешь ситуацию когда у тебя нет labeled data для eval?**  
_Synthetic generation; human review выборки; seed questions от domain experts_

---

# 💻 CODING / ПРАКТИЧЕСКИЕ ЗАДАЧИ

> Встречаются в 60-80% компаний с техническим скринингом

`[70/100]` **Реализуй простой RAG pipeline (code sketch):**  
```python
# Embed documents → store in ChromaDB → retrieve by query → pass to LLM
```

`[68/100]` **Реализуй cosine similarity без библиотек:**  
```python
def cosine_similarity(a, b):
    dot = sum(x*y for x, y in zip(a, b))
    norm_a = sum(x**2 for x in a) ** 0.5
    norm_b = sum(x**2 for x in b) ** 0.5
    return dot / (norm_a * norm_b)
```

`[65/100]` **Реализуй retry с exponential backoff:**  
```python
import time, random
def llm_call_with_retry(fn, max_retries=3):
    for i in range(max_retries):
        try: return fn()
        except Exception:
            time.sleep((2**i) + random.random())
    raise Exception("Max retries exceeded")
```

`[63/100]` **Реализуй базовый agent loop с tool dispatch:**  
```python
# while not done: get action from LLM → dispatch tool → add to history → repeat
```

`[60/100]` **Реализуй chunking текста с overlap:**  
```python
def chunk_text(text, chunk_size=500, overlap=50):
    chunks = []
    start = 0
    while start < len(text):
        chunks.append(text[start:start+chunk_size])
        start += chunk_size - overlap
    return chunks
```

`[58/100]` **Напиши async функцию для параллельных LLM вызовов:**  
```python
async def parallel_llm_calls(prompts):
    tasks = [llm_async(p) for p in prompts]
    return await asyncio.gather(*tasks)
```

---

# 🎯 ЧТО РЕАЛЬНО ВАЖНО ДЛЯ LOW-BARRIER КОМПАНИЙ

Паттерн от компаний с низким порогом (стартапы, аутсорс, ранние AI-продукты):

**Сокращённый технический экран (1-2 часа):**
1. Объясни RAG (без этого не берут)
2. Напиши/покажи код простого AI фичи
3. Как ты будешь дебажить если что-то пойдёт не так
4. Soft skills: обучаемость, любопытство

**Чего НЕ спрашивают в low-barrier:**
- Производная softmax вручную
- Доказательства теорем ML
- Реализация transformer с нуля
- Математика RLHF

**Что реально выделяет junior кандидата:**
- Есть хоть один реальный RAG/agent проект (даже pet project)
- Может объяснить что пошло не так и как исправил
- Знает реальные инструменты: LangChain/LangGraph, ChromaDB/pgvector, LangFuse
- Понимает cost vs latency vs quality triangle

---

_Источники: ~100 русских и английских статей, Habr, tproger, Medium, GitHub repos, dev.to за 2025–2026. Полный список в файле interview_questions_sources.md_
