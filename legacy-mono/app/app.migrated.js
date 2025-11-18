// app.js
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
  DB_PASS = "apppass",           // legacy name
  DB_PASSWORD,                   
  STORAGE = "local",
  S3_BUCKET = "",
  S3_PREFIX = "uploads/"
} = process.env;


const dbPassword = DB_PASSWORD || DB_PASS;

// Build pool config with optional SSL for RDS
const isLocalHost =
  DB_HOST === "localhost" || DB_HOST === "127.0.0.1";

const poolConfig = {
  host: DB_HOST,
  port: Number(DB_PORT),
  database: DB_NAME,
  user: DB_USER,
  password: dbPassword
};

// For RDS / non-local DBs, enable SSL
if (!isLocalHost) {
  poolConfig.ssl = { rejectUnauthorized: false };
}

const pool = new Pool(poolConfig);

// Storage setup (local or S3)
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

// Simple health/config endpoint
app.get("/", (_, res) => {
  res.json({
    ok: true,
    storage: STORAGE,
    db: {
      host: DB_HOST,
      name: DB_NAME,
      user: DB_USER,
      ssl: !isLocalHost
    }
  });
});

// Get notes (DB-backed)
app.get("/notes", async (_, res) => {
  try {
    const { rows } = await pool.query(
      "SELECT id, body FROM notes ORDER BY id DESC"
    );
    res.json(rows);
  } catch (err) {
    console.error("Error in GET /notes:", err);
    res.status(500).json({ ok: false, error: "DB_ERROR" });
  }
});

// Create note
app.post("/notes", async (req, res) => {
  try {
    const { body } = req.body || {};
    const result = await pool.query(
      "INSERT INTO notes(body) VALUES($1) RETURNING id, body",
      [body || ""]
    );
    res.json(result.rows[0]);
  } catch (err) {
    console.error("Error in POST /notes:", err);
    res.status(500).json({ ok: false, error: "DB_ERROR" });
  }
});

// File upload (local or S3)
app.post("/upload", upload.single("file"), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: "no file" });

  try {
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
  } catch (err) {
    console.error("Error in POST /upload:", err);
    res.status(500).json({ ok: false, error: "UPLOAD_ERROR" });
  }
});

app.listen(PORT, () => {
  console.log(
    `App on :${PORT}, storage=${STORAGE}, dbHost=${DB_HOST}, ssl=${!isLocalHost}`
  );
});
