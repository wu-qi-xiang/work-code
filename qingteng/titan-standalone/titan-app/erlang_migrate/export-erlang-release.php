<?php

use QT2\Components\Auth\Users\User;
use QT2\Config;
use QT\Components\Services\UpgradeService;

require_once 'base.php';

qtboot(function ($argc, $argv) {
    if ($argc < 2) {
        echo "use php {$argv[0]} dir\n";
        exit(1);
    }

    $dir = $argv[1];

    $schemas = [
        ['os' => 'linux', 'arch' => 'x86_64'],
        ['os' => 'linux', 'arch' => 'x86'],
        ['os' => 'windows', 'arch' => 'x86_64'],
        ['os' => 'windows', 'arch' => 'x86'],
        ['os' => 'aix', 'arch' => 'ppc64'],
        ['os' => 'solaris', 'arch' => 'x86_64'],
        ['os' => 'solaris', 'arch' => 'sparc64']
    ];

    $data = [];
    $service = new UpgradeService();

    $uuids = (new User())->findColumn(['owner' => 0], 'uuid');
    if (!$uuids) {
        $uuids[] = 'default';
    }
    
    $ver_map = [];
    foreach ($schemas as $schema) {
        foreach ($uuids as $uuid) {
            $release = get_erlang_release($service, $uuid, $schema['os'], $schema['arch']);
            if ($release && !array_key_exists($release['version'], $ver_map)) {
                $data[] = $release;
                $ver_map[$release['version']] = 1;
            }
        }
    }

    $filename = $dir . '/' . 'erlang_release.json';
    file_put_contents($filename, json_encode($data, JSON_PRETTY_PRINT));
}, $argc, $argv);

/**
 * @param UpgradeService $service
 * @param type $os
 * @param type $arch
 * @return type
 */
function get_erlang_release($service, $comid, $os, $arch) {
    $qtver = Config::getInstance()->version();
    $major = strtolower(substr($qtver, 0, 4));
    
    $erl_arch = $arch;
    if ($major !== 'v3.3' && $arch === 'x86_64') {
        $erl_arch = 'x64';
    }
    
    $result = $service->getConf($comid, $os, $erl_arch);
    if ($result) {
        return build_release($os, $arch, $result);
    } else if (is_release_required($os, $arch)) {
        echo "export erlang release failed os: {$os} arch: {$arch}}\n";
        exit(1);
    } else {
        return null;
    }
}

function build_release($os, $arch, $result) {
    $agent = $result['agent'];
    return [
        'os' => $os,
        'arch' => $arch,
        'update_file_path' => basename($agent['url']),
        'install_file_path' => basename($agent['script_url']),
        'version' => $agent['vsn'],
        'base_url' => get_base_url($agent['url']),
        'base_url_ipv6' => get_base_url($agent['url6']),
        'so_plugins' => encode_so_plugins($result['plugins']),
        'lua_plugins' => get_lua_plugins($os, $arch)
    ];
}

function is_release_required($os, $arch) {
    if ($os === 'linux' && $arch === 'x86_64') {
        return true;
    }

    if ($os === 'windows' && $arch === 'x86_64') {
        return true;
    }

    return false;
}

function get_base_url($url) {
    if ($url) {
        $pos = strrpos($url, '/');
        if ($pos === false) {
            echo "invalid release url: {$url}\n";
            exit(1);
        }
        return substr($url, 0, $pos);
    } else {
        return '';
    }
}

function encode_so_plugins($plugins) {
    $results = [];
    foreach ($plugins as $data) {
        $results[] = [
            'id' => $data['id'],
            'name' => $data['name'],
            'version' => $data['vsn'],
            'file_path' => get_so_plugin_path($data['url'])
        ];
    }
    return $results;
}

function get_so_plugin_path($url) {
    if ($url) {
        $pos = strrpos($url, '/');
        if ($pos === false) {
            echo "invalid plugin url: {$url}\n";
            exit(1);
        }
        return substr($url, $pos + 1);
    } else {
        echo "invalid plugin url: {$url}\n";
        exit(1);
    }
}

function get_lua_plugins($os, $arch) {
    $array = [
        'linux:x86_64' => [
            [
                'id' => '0x21000000',
                'name' => 'shellaudit_logsrv.lua',
                'version' => '1.0.0',
                'script_id' => 'agent.auditshell.linux.logsrv_shellaudit'
            ],
            [
                'id' => '0x30000000',
                'name' => 'basic_data.lua',
                'version' => '1.0.0',
                'script_id' => 'agent.basic_data.linux.basic_data'
            ],
            [
                'id' => '0x25000000',
                'name' => 'netlink_monitor.lua',
                'version' => '1.0.0',
                'script_id' => 'agent.monitor.linux.netlink_monitor'
            ],
            [
                'id' => '0x26000000',
                'name' => 'account_monitor.lua',
                'version' => '1.0.0',
                'script_id' => 'agent.collectinfo.linux.account_monitor'
            ]
        ],
        'linux:x86' => [
            [
                'id' => '0x30000000',
                'name' => 'basic_data.lua',
                'version' => '1.0.0',
                'script_id' => 'agent.basic_data.linux.basic_data'
            ]
        ],
        'windows:x86_64' => [
            [
                'id' => '0x30000000',
                'name' => 'basic_data_windows.lua',
                'version' => '1.0.0',
                'script_id' => 'agent.basic_data.windows.basic_data'
            ],
            [
                'id' => '0x34000000',
                'name' => 'winlogon_monitor_srv.lua',
                'version' => '1.0.0',
                'script_id' => 'agent.bruteforce.windows.winlogon_monitor'
            ]
        ],
        'windows:x86' => [
            [
                'id' => '0x30000000',
                'name' => 'basic_data_windows.lua',
                'version' => '1.0.0',
                'script_id' => 'agent.basic_data.windows.basic_data'
            ]
        ],
        'solaris:x86_64' => [
            [
                'id' => '0x30000000',
                'name' => 'basic_data_solaris.lua',
                'version' => '1.0.0',
                'script_id' => 'agent.basic_data.solaris.basic_data'
            ]
        ],
        'solaris:sparc64' => [
            [
                'id' => '0x30000000',
                'name' => 'basic_data_solaris.lua',
                'version' => '1.0.0',
                'script_id' => 'agent.basic_data.solaris.basic_data'
            ]
        ],
        'aix:ppc64' => [
            [
                'id' => '0x30000000',
                'name' => 'basic_data_aix.lua',
                'version' => '1.0.0',
                'script_id' => 'agent.basic_data.aix.basic_data'
            ]
        ]
    ];

    $key = "{$os}:{$arch}";
    if (array_key_exists($key, $array)) {
        return $array[$key];
    } else {
        echo "lua plugin not found for: {$key}\n";
        exit(1);
    }
}