import sqlite3
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

DB_PATH = Path(__file__).parent / "app.db"


def get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


@asynccontextmanager
async def lifespan(app: FastAPI):
    with get_conn() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                description TEXT,
                price REAL NOT NULL DEFAULT 0
            )
            """
        )
    yield


app = FastAPI(title="CRUD Deploy Test", lifespan=lifespan)


class ItemIn(BaseModel):
    name: str
    description: str | None = None
    price: float = 0


class Item(ItemIn):
    id: int


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/items", response_model=list[Item])
def list_items():
    with get_conn() as conn:
        rows = conn.execute("SELECT * FROM items ORDER BY id").fetchall()
    return [dict(row) for row in rows]


@app.get("/items/{item_id}", response_model=Item)
def get_item(item_id: int):
    with get_conn() as conn:
        row = conn.execute("SELECT * FROM items WHERE id = ?", (item_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Item not found")
    return dict(row)


@app.post("/items", response_model=Item, status_code=201)
def create_item(item: ItemIn):
    with get_conn() as conn:
        cur = conn.execute(
            "INSERT INTO items (name, description, price) VALUES (?, ?, ?)",
            (item.name, item.description, item.price),
        )
        new_id = cur.lastrowid
    return {**item.model_dump(), "id": new_id}


@app.put("/items/{item_id}", response_model=Item)
def update_item(item_id: int, item: ItemIn):
    with get_conn() as conn:
        row = conn.execute("SELECT id FROM items WHERE id = ?", (item_id,)).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Item not found")
        conn.execute(
            "UPDATE items SET name = ?, description = ?, price = ? WHERE id = ?",
            (item.name, item.description, item.price, item_id),
        )
    return {**item.model_dump(), "id": item_id}


@app.delete("/items/{item_id}", status_code=204)
def delete_item(item_id: int):
    with get_conn() as conn:
        row = conn.execute("SELECT id FROM items WHERE id = ?", (item_id,)).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Item not found")
        conn.execute("DELETE FROM items WHERE id = ?", (item_id,))
