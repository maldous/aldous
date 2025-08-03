<?php

namespace Tests\Unit;

use Tests\TestCase;

class EnvTest extends TestCase
{
    protected array $vars = [
        'APP_NAME','APP_ENV','APP_KEY','APP_DEBUG','APP_URL',
        'APP_LOCALE','APP_FALLBACK_LOCALE','APP_FAKER_LOCALE',
        'APP_MAINTENANCE_STORE','PHP_CLI_SERVER_WORKERS',
        'BCRYPT_ROUNDS','LOG_CHANNEL','LOG_STACK',
        'LOG_DEPRECATIONS_CHANNEL','LOG_LEVEL','DB_CONNECTION',
        'DB_HOST','DB_PORT','DB_DATABASE','DB_USERNAME',
        'DB_PASSWORD','SESSION_DRIVER','SESSION_LIFETIME',
        'SESSION_ENCRYPT','SESSION_PATH','SESSION_DOMAIN',
        'BROADCAST_CONNECTION','FILESYSTEM_DISK','QUEUE_CONNECTION',
        'CACHE_STORE','CACHE_PREFIX','MEMCACHED_HOST',
        'REDIS_CLIENT','REDIS_HOST','REDIS_PASSWORD',
        'REDIS_PORT','MAIL_MAILER','MAIL_SCHEME','MAIL_HOST',
        'MAIL_PORT','MAIL_USERNAME','MAIL_PASSWORD',
        'MAIL_FROM_ADDRESS','MAIL_FROM_NAME','AWS_ACCESS_KEY_ID',
        'AWS_SECRET_ACCESS_KEY','AWS_DEFAULT_REGION','AWS_BUCKET',
        'AWS_USE_PATH_STYLE_ENDPOINT','VITE_APP_NAME',
    ];


    public function test_all_env_vars_are_defined()
    {
        foreach ($this->vars as $key) {
            $val = env($key, '__missing__');
            $this->assertNotSame(
                '__missing__',
                $val,
                "Missing {$key}"
            );
        }
    }

    public function test_app_key_format()
    {
        $this->assertMatchesRegularExpression(
            '/^base64:[A-Za-z0-9\/+=]+$/',
            env('APP_KEY'),
            'APP_KEY is invalid'
        );
    }

    public function test_boolean_vars_are_boolean()
    {
        foreach (['APP_DEBUG','SESSION_ENCRYPT','AWS_USE_PATH_STYLE_ENDPOINT'] as $key) {
            $val = env($key);
            $this->assertTrue(
                is_bool($val),
                "{$key} is not boolean"
            );
        }
    }

    public function test_numeric_vars_are_numeric()
    {
        foreach ([
            'PHP_CLI_SERVER_WORKERS','BCRYPT_ROUNDS',
            'DB_PORT','SESSION_LIFETIME',
            'REDIS_PORT','MAIL_PORT',
        ] as $key) {
            $this->assertTrue(
                is_numeric(env($key)),
                "{$key} is not numeric"
            );
        }
    }

    public function test_app_url_is_valid()
    {
        $this->assertTrue(
            filter_var(env('APP_URL'), FILTER_VALIDATE_URL) !== false,
            'APP_URL is invalid'
        );
    }

    public function test_names_match_app_name()
    {
        $this->assertSame(env('APP_NAME'), env('MAIL_FROM_NAME'));
        $this->assertSame(env('APP_NAME'), env('VITE_APP_NAME'));
    }
}
