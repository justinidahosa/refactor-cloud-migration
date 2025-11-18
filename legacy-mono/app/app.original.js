import express from "express";
import multer from "multer";
import { Pool } from "pg";
import fs from "fs";
import path from "path";
import dotenv from "dotenv";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";

dotenv.config();

const app = express();
app.use(express.json());

const {
  PORT = 3000,
  DB_HOST = "localhost",
  DB_PORT = 5432,
  DB_NAME = "appdb",
  DB_USER = "appuser",
  DB_PASS = "apppass",
  STORAGE = "local",
  S3_BUCKET = "",
  S3_PREFIX = "uploads/"
} = process.env;

const pool = new Pool({
  host: DB_HOST,
  port: Number(DB_PORT),
  database: DB_NAME,
  user: DB_USER,
  password: DB_PASS
});

let upload;
let s3;

if (STORAGE === "s3") {
  upload = multer({ storage: multer.memoryStorage() });
  s3 = new S3Client({});
} else {
  const uploadsDir = path.join(process.cwd(), "uploads");
  if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
  }
  upload = multer({ dest: "uploads" });
}

app.get("/", (_, res) => {
  res.json({ ok: true, storage: STORAGE });
});

app.get("/notes", async (_, res) => {
  const { rows } = await pool.query(
    "select id, body from notes order by id desc"
  );
  res.json(rows);
});

app.post("/notes", async (req, res) => {
  const { body } = req.body || {};
  const result = await pool.query(
    "insert into notes(body) values($1) returning id, body",
    [body || ""]
  );
  res.json(result.rows[0]);
});

app.post("/upload", upload.single("file"), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: "no file" });
  }

  if (STORAGE === "s3") {
    const key = `${S3_PREFIX}${Date.now()}-${req.file.originalname}`;
    await s3.send(
      new PutObjectCommand({
        Bucket: S3_BUCKET,
        Key: key,
        Body: req.file.buffer,
        ContentType: req.file.mimetype
      })
    );
    return res.json({ uploaded: "s3", bucket: S3_BUCKET, key });
  } else {
    return res.json({ uploaded: "local", path: req.file.path });
  }
});

app.listen(PORT, () => {
  console.log(`App on :${PORT}, storage=${STORAGE}`);
});
