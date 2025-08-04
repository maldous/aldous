<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

Route::get('/callback', function () {
    return redirect('/');
});

Route::get('/dump', function (Illuminate\Http\Request $r) {
    return response()->json($r->headers->all());
});
