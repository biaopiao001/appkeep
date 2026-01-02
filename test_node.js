#!/usr/bin/env node

console.log('=== Node.js 环境测试 ===');
console.log('Node.js 版本:', process.version);
console.log('当前工作目录:', process.cwd());
console.log('');

console.log('=== 环境变量 ===');
console.log('NODE_ENV:', process.env.NODE_ENV || '未设置');
console.log('PATH:', process.env.PATH);
console.log('HOME:', process.env.HOME);
console.log('USER:', process.env.USER);
console.log('CUSTOM_VAR:', process.env.CUSTOM_VAR || '未设置');
console.log('');

console.log('=== 可用模块路径 ===');
console.log('NODE_PATH:', process.env.NODE_PATH || '未设置');
console.log('模块搜索路径:', require.resolve.paths(''));
console.log('');

console.log('=== 进程信息 ===');
console.log('进程 ID:', process.pid);
console.log('父进程 ID:', process.ppid);
console.log('平台:', process.platform);
console.log('架构:', process.arch);
console.log('');

console.log('=== 环境变量总数 ===');
console.log('总计:', Object.keys(process.env).length, '个环境变量');