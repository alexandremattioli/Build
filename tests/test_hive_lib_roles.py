from scripts.bootstrap.ubuntu24.hive_lib import suggest_cloudstack_role


def test_first_management_server():
    peers = []
    advice = suggest_cloudstack_role(peers)
    assert advice['role'] == 'management-server'
    assert 'mysql-server' in advice['packages']


def test_second_role_cloudstack_builder_needed():
    peers = [ {'role': 'management-server'} ]
    advice = suggest_cloudstack_role(peers)
    assert advice['role'] == 'cloudstack-builder'
    assert 'maven' in advice['packages']


def test_hypervisor_after_two_builders():
    peers = [ {'role': 'management-server'}, {'role': 'cloudstack-builder'}, {'role': 'cloudstack-builder'} ]
    advice = suggest_cloudstack_role(peers)
    assert advice['role'] == 'kvm-hypervisor'
    assert 'qemu-kvm' in advice['packages']


def test_vnf_tester_when_broker_available():
    peers = [ {'role': 'management-server'}, {'role': 'cloudstack-builder'}, {'role': 'cloudstack-builder'}, {'role': 'kvm-hypervisor'} ]
    advice = suggest_cloudstack_role(peers, vnf_available=True)
    assert advice['role'] == 'vnf-tester'
    assert 'docker.io' in advice['packages']


def test_default_test_runner_when_all_present():
    peers = [
        {'role': 'management-server'},
        {'role': 'cloudstack-builder'},
        {'role': 'cloudstack-builder'},
        {'role': 'kvm-hypervisor'},
        {'role': 'vnf-tester'},
    ]
    advice = suggest_cloudstack_role(peers)
    assert advice['role'] == 'test-runner'
    assert any('pytest' in p for p in advice['packages'])
