import json
import logging
import os
import re
import secrets
import string
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import RedirectResponse
from pydantic import AnyHttpUrl, BaseModel, Field

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("url-shortener")

CLOUD_PROVIDER = os.getenv("CLOUD_PROVIDER", "local").lower()
GCP_PROJECT_ID = os.getenv("GCP_PROJECT_ID", "damis-project-01")
FIRESTORE_DATABASE = os.getenv("FIRESTORE_DATABASE", "(default)")
FIRESTORE_COLLECTION = os.getenv("FIRESTORE_COLLECTION", "short_links")
BIGQUERY_DATASET = os.getenv("BIGQUERY_DATASET", "url_analytics")
BIGQUERY_TABLE = os.getenv("BIGQUERY_TABLE", "click_events")

AZURE_COSMOS_ENDPOINT = os.getenv("AZURE_COSMOS_ENDPOINT", "")
AZURE_COSMOS_DATABASE = os.getenv("AZURE_COSMOS_DATABASE", "shortenerdb")
AZURE_COSMOS_CONTAINER = os.getenv("AZURE_COSMOS_CONTAINER", "urls")

SLUG_ALPHABET = string.ascii_letters + string.digits
CUSTOM_CODE_PATTERN = re.compile(r"^[a-zA-Z0-9_-]{3,32}$")
RESERVED_PATHS = {"health", "shorten", "stats", "docs", "openapi.json", "redoc"}

app = FastAPI(
    title="Multi-Cloud URL Shortener & Edge Analytics",
    description="Serverless URL shortener with real-time edge click telemetry across GCP (Firestore + BigQuery) and Azure (Cosmos DB + Log Analytics).",
    version="1.0.0",
)

_memory_store: Dict[str, Dict[str, Any]] = {}
_firestore_client = None
_bigquery_client = None
_cosmos_container = None


def get_firestore_client():
    global _firestore_client
    if _firestore_client is None:
        from google.cloud import firestore
        _firestore_client = firestore.Client(project=GCP_PROJECT_ID, database=FIRESTORE_DATABASE)
    return _firestore_client


def get_bigquery_client():
    global _bigquery_client
    if _bigquery_client is None:
        from google.cloud import bigquery
        _bigquery_client = bigquery.Client(project=GCP_PROJECT_ID)
    return _bigquery_client


def get_cosmos_container():
    global _cosmos_container
    if _cosmos_container is None:
        from azure.cosmos import CosmosClient
        from azure.identity import DefaultAzureCredential

        credential = DefaultAzureCredential()
        client = CosmosClient(url=AZURE_COSMOS_ENDPOINT, credential=credential)
        db = client.get_database_client(AZURE_COSMOS_DATABASE)
        _cosmos_container = db.get_container_client(AZURE_COSMOS_CONTAINER)
    return _cosmos_container


class ShortenRequest(BaseModel):
    url: AnyHttpUrl
    custom_code: Optional[str] = Field(
        default=None,
        description="Optional custom slug (3-32 alphanumeric characters, hyphens, or underscores)",
    )


class ShortenResponse(BaseModel):
    code: str
    short_url: str
    target_url: str
    created_at: str
    cloud: str


def _generate_code(length: int = 6) -> str:
    while True:
        candidate = "".join(secrets.choice(SLUG_ALPHABET) for _ in range(length))
        if candidate.lower() not in RESERVED_PATHS:
            return candidate


def _get_link(code: str) -> Optional[Dict[str, Any]]:
    try:
        if CLOUD_PROVIDER == "gcp":
            doc = get_firestore_client().collection(FIRESTORE_COLLECTION).document(code).get()
            return doc.to_dict() if doc.exists else None

        if CLOUD_PROVIDER == "azure":
            from azure.cosmos.exceptions import CosmosResourceNotFoundError
            try:
                return get_cosmos_container().read_item(item=code, partition_key=code)
            except CosmosResourceNotFoundError:
                return None

        return _memory_store.get(code)
    except Exception as exc:
        logger.exception("Storage read failure for code=%s on cloud=%s", code, CLOUD_PROVIDER)
        raise HTTPException(status_code=502, detail=f"Storage read error ({CLOUD_PROVIDER}): {exc}")


def _save_link(record: Dict[str, Any]) -> None:
    code = record["code"]
    try:
        if CLOUD_PROVIDER == "gcp":
            get_firestore_client().collection(FIRESTORE_COLLECTION).document(code).set(record)
            return

        if CLOUD_PROVIDER == "azure":
            cosmos_doc = {**record, "id": code}
            get_cosmos_container().create_item(body=cosmos_doc)
            return

        _memory_store[code] = record
    except Exception as exc:
        logger.exception("Storage write failure for code=%s on cloud=%s", code, CLOUD_PROVIDER)
        raise HTTPException(status_code=502, detail=f"Storage write error ({CLOUD_PROVIDER}): {exc}")


def _record_click(code: str, record: Dict[str, Any], event: Dict[str, Any]) -> None:
    updated_clicks = int(record.get("clicks", 0)) + 1
    recent_events = list(record.get("recent_events", []))
    recent_events.append(event)
    recent_events = recent_events[-25:]

    logger.info(json.dumps({"event_type": "edge_click", **event}))

    try:
        if CLOUD_PROVIDER == "gcp":
            get_firestore_client().collection(FIRESTORE_COLLECTION).document(code).update(
                {"clicks": updated_clicks, "recent_events": recent_events}
            )
            table_ref = f"{GCP_PROJECT_ID}.{BIGQUERY_DATASET}.{BIGQUERY_TABLE}"
            errors = get_bigquery_client().insert_rows_json(table_ref, [event])
            if errors:
                logger.warning(json.dumps({"warning": "bigquery_insert_errors", "details": errors}))
            return

        if CLOUD_PROVIDER == "azure":
            cosmos_doc = {
                **record,
                "id": code,
                "clicks": updated_clicks,
                "recent_events": recent_events,
            }
            get_cosmos_container().upsert_item(body=cosmos_doc)
            return

        record["clicks"] = updated_clicks
        record["recent_events"] = recent_events
    except Exception as exc:
        logger.exception("Telemetry update failed for code=%s on cloud=%s: %s", code, CLOUD_PROVIDER, exc)


@app.get("/")
def root(request: Request) -> Dict[str, Any]:
    base = str(request.base_url).rstrip("/")
    return {
        "service": "Multi-Cloud URL Shortener & Edge Analytics",
        "cloud": CLOUD_PROVIDER,
        "endpoints": {
            "health": f"{base}/health",
            "docs": f"{base}/docs",
            "shorten": f"POST {base}/shorten",
            "redirect": f"GET {base}/{{code}}",
            "stats": f"GET {base}/stats/{{code}}",
        },
    }


@app.get("/health")
def health() -> Dict[str, str]:
    backends = {
        "gcp": ("Cloud Firestore", "BigQuery + Cloud Logging"),
        "azure": ("Azure Cosmos DB (Serverless)", "Azure Log Analytics Workspace"),
        "local": ("In-Memory Store", "Structured Stdout Telemetry"),
    }
    store_name, analytics_name = backends.get(CLOUD_PROVIDER, ("Unknown", "Unknown"))
    return {
        "status": "healthy",
        "service": "multicloud-url-shortener",
        "cloud": CLOUD_PROVIDER,
        "store_backend": store_name,
        "analytics_backend": analytics_name,
    }


@app.post("/shorten", response_model=ShortenResponse, status_code=201)
def shorten_url(payload: ShortenRequest, request: Request) -> ShortenResponse:
    if payload.custom_code:
        code = payload.custom_code.strip()
        if code.lower() in RESERVED_PATHS or not CUSTOM_CODE_PATTERN.match(code):
            raise HTTPException(
                status_code=400,
                detail="Invalid custom_code: must be 3-32 chars (letters, numbers, -, _) and not a reserved route.",
            )
        if _get_link(code) is not None:
            raise HTTPException(status_code=409, detail=f"Short code '{code}' is already in use.")
    else:
        code = _generate_code()
        while _get_link(code) is not None:
            code = _generate_code()

    created_at = datetime.now(timezone.utc).isoformat()
    target_url = str(payload.url)
    record = {
        "code": code,
        "target_url": target_url,
        "created_at": created_at,
        "clicks": 0,
        "recent_events": [],
    }
    _save_link(record)

    base_url = str(request.base_url).rstrip("/")
    return ShortenResponse(
        code=code,
        short_url=f"{base_url}/{code}",
        target_url=target_url,
        created_at=created_at,
        cloud=CLOUD_PROVIDER,
    )


@app.get("/stats/{code}")
def get_stats(code: str) -> Dict[str, Any]:
    record = _get_link(code)
    if record is None:
        raise HTTPException(status_code=404, detail="Short URL not found")

    bq_clicks: Optional[int] = None
    if CLOUD_PROVIDER == "gcp":
        try:
            query = f"""
                SELECT COUNT(*) AS total
                FROM `{GCP_PROJECT_ID}.{BIGQUERY_DATASET}.{BIGQUERY_TABLE}`
                WHERE code = @code
            """
            from google.cloud import bigquery
            job_config = bigquery.QueryJobConfig(
                query_parameters=[bigquery.ScalarQueryParameter("code", "STRING", code)]
            )
            rows = list(get_bigquery_client().query(query, job_config=job_config).result())
            if rows:
                bq_clicks = int(rows[0].total)
        except Exception as exc:
            logger.warning(json.dumps({"warning": "bigquery_query_skipped", "error": str(exc)}))

    return {
        "code": record["code"],
        "target_url": record["target_url"],
        "created_at": record["created_at"],
        "cloud": CLOUD_PROVIDER,
        "total_clicks": record.get("clicks", 0),
        "bigquery_verified_clicks": bq_clicks,
        "recent_events": record.get("recent_events", []),
    }


@app.get("/{code}")
def redirect_to_target(code: str, request: Request) -> RedirectResponse:
    record = _get_link(code)
    if record is None:
        raise HTTPException(status_code=404, detail="Short URL not found")

    forwarded_for = request.headers.get("x-forwarded-for", "")
    client_ip = forwarded_for.split(",")[0].strip() if forwarded_for else (
        request.client.host if request.client else "unknown"
    )
    edge_region = (
        request.headers.get("x-cloud-trace-context")
        and os.getenv("CLOUD_RUN_REGION", "us-central1")
        or request.headers.get("x-azure-ref")
        and os.getenv("AZURE_REGION", "eastus")
        or CLOUD_PROVIDER
    )

    event = {
        "code": code,
        "target_url": record["target_url"],
        "clicked_at": datetime.now(timezone.utc).isoformat(),
        "user_agent": request.headers.get("user-agent", "unknown"),
        "referer": request.headers.get("referer", "direct"),
        "client_ip": client_ip,
        "edge_region": edge_region,
        "cloud": CLOUD_PROVIDER,
    }
    _record_click(code, record, event)
    return RedirectResponse(url=record["target_url"], status_code=302)
