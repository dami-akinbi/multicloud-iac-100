from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "healthy"
    assert body["cloud"] == "local"


def test_shorten_redirect_and_stats_flow():
    # 1. Create a short URL with a custom slug
    create_res = client.post(
        "/shorten",
        json={
            "url": "https://github.com/dami-akinbi/multicloud-iac-100",
            "custom_code": "portfolio-100",
        },
    )
    assert create_res.status_code == 201
    created = create_res.json()
    assert created["code"] == "portfolio-100"
    assert created["short_url"].endswith("/portfolio-100")

    # 2. Verify duplicate custom code returns 409 Conflict
    dup_res = client.post(
        "/shorten",
        json={
            "url": "https://example.com",
            "custom_code": "portfolio-100",
        },
    )
    assert dup_res.status_code == 409

    # 3. Follow redirect without auto-following external URL
    redirect_res = client.get("/portfolio-100", follow_redirects=False)
    assert redirect_res.status_code == 302
    assert redirect_res.headers["location"] == "https://github.com/dami-akinbi/multicloud-iac-100"

    # 4. Verify edge click telemetry was captured in stats
    stats_res = client.get("/stats/portfolio-100")
    assert stats_res.status_code == 200
    stats = stats_res.json()
    assert stats["total_clicks"] == 1
    assert len(stats["recent_events"]) == 1
    assert stats["recent_events"][0]["code"] == "portfolio-100"
