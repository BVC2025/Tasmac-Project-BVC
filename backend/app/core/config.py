from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "TASMAC Bottle Return API"
    app_env: str = "development"
    debug: bool = True

    database_url: str = "postgresql+psycopg2://postgres:postgres@localhost:5432/tasmac_bottle_return"

    secret_key: str = "dev-only-insecure-secret-key"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 12

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
