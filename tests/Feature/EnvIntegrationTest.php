<?php

namespace Tests\Feature;

use Tests\TestCase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Aws\S3\S3Client;

class EnvIntegrationTest extends TestCase
{
    public function test_database_connection_works()
    {
        $driver = config('database.default');
        $ext    = 'pdo_'.$driver;

        if (! extension_loaded($ext)) {
            $this->markTestSkipped("PDO driver {$ext} not installed");
        }

        DB::connection()->getPdo();
        $this->assertTrue(true);
    }

    public function test_memcached_store_if_available()
    {
        if (! extension_loaded('memcached')) {
            $this->markTestSkipped('Memcached extension not installed');
        }

        try {
            Cache::store('memcached')->put('env_test', 'ok', 1);
            $val = Cache::store('memcached')->get('env_test');
        } catch (\Exception $e) {
            $this->markTestSkipped('Memcached not available');
        }

        if ($val === null) {
            $this->markTestSkipped('Memcached server not reachable');
        }

        $this->assertSame('ok', $val);
    }

    public function test_redis_connection_if_available()
    {
        if (! extension_loaded('redis')) {
            $this->markTestSkipped('Redis extension not installed');
        }

        try {
            $pong = Redis::connection()->ping();
        } catch (\Exception $e) {
            $this->markTestSkipped('Redis server not reachable');
        }

        $this->assertTrue(
            $pong === 'PONG' || $pong === true,
            'Redis ping failed'
        );
    }

    public function test_s3_minio_bucket_if_sdk_present()
    {
        if (! class_exists(S3Client::class)) {
            $this->markTestSkipped('AWS SDK not installed');
        }

        $client = new S3Client([
            'version'                 => 'latest',
            'region'                  => env('AWS_DEFAULT_REGION'),
            'endpoint'                => env('AWS_ENDPOINT', 'http://127.0.0.1:9000'),
            'use_path_style_endpoint' => env('AWS_USE_PATH_STYLE_ENDPOINT'),
            'credentials'             => [
                'key'    => env('AWS_ACCESS_KEY_ID'),
                'secret' => env('AWS_SECRET_ACCESS_KEY'),
            ],
        ]);

        try {
            $client->headBucket(['Bucket' => env('AWS_BUCKET')]);
        } catch (\Exception $e) {
            $this->markTestSkipped('S3/MinIO bucket not reachable');
        }

        $this->assertTrue(true);
    }
}

