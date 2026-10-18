#include "../../Zsign/src/ocsp_response.hpp"
#include <openssl/evp.h>
#include <openssl/rsa.h>
#include <openssl/x509.h>
#include <cassert>
#include <cstdio>
#include <vector>

template<class T, void (*Free)(T*)>
using Owned = std::unique_ptr<T, decltype(Free)>;

std::vector<unsigned char> encode(OCSP_RESPONSE* response) {
    const int length = i2d_OCSP_RESPONSE(response, nullptr);
    assert(length > 0);
    std::vector<unsigned char> bytes(length);
    unsigned char* cursor = bytes.data();
    assert(i2d_OCSP_RESPONSE(response, &cursor) == length);
    return bytes;
}

Owned<X509, X509_free> certificate(EVP_PKEY* key, long serial) {
    Owned<X509, X509_free> cert(X509_new(), X509_free);
    assert(cert && X509_set_version(cert.get(), 2) == 1);
    assert(ASN1_INTEGER_set(X509_get_serialNumber(cert.get()), serial) == 1);
    X509_gmtime_adj(X509_getm_notBefore(cert.get()), -60);
    X509_gmtime_adj(X509_getm_notAfter(cert.get()), 3600);
    assert(X509_set_pubkey(cert.get(), key) == 1);
    auto* name = X509_get_subject_name(cert.get());
    assert(X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC,
        reinterpret_cast<const unsigned char*>("Offline OCSP regression"), -1, -1, 0) == 1);
    assert(X509_set_issuer_name(cert.get(), name) == 1);
    assert(X509_sign(cert.get(), key, EVP_sha256()) > 0);
    return cert;
}

std::vector<unsigned char> responseFor(OCSP_CERTID* id, int status, X509* issuer, EVP_PKEY* key) {
    Owned<OCSP_BASICRESP, OCSP_BASICRESP_free> basic(OCSP_BASICRESP_new(), OCSP_BASICRESP_free);
    Owned<ASN1_TIME, ASN1_TIME_free> start(ASN1_TIME_adj(nullptr, time(nullptr), 0, -10), ASN1_TIME_free);
    Owned<ASN1_TIME, ASN1_TIME_free> end(ASN1_TIME_adj(nullptr, time(nullptr), 0, 3600), ASN1_TIME_free);
    Owned<ASN1_TIME, ASN1_TIME_free> revoked(ASN1_TIME_adj(nullptr, time(nullptr), 0, -30), ASN1_TIME_free);
    assert(OCSP_basic_add1_status(basic.get(), id, status, OCSP_REVOKED_STATUS_KEYCOMPROMISE,
        status == V_OCSP_CERTSTATUS_REVOKED ? revoked.get() : nullptr, start.get(), end.get()));
    assert(OCSP_basic_sign(basic.get(), issuer, key, EVP_sha256(), nullptr, 0) == 1);
    Owned<OCSP_RESPONSE, OCSP_RESPONSE_free> response(
        OCSP_response_create(OCSP_RESPONSE_STATUS_SUCCESSFUL, basic.get()), OCSP_RESPONSE_free);
    return encode(response.get());
}

int main() {
    Owned<EVP_PKEY_CTX, EVP_PKEY_CTX_free> ctx(EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, nullptr), EVP_PKEY_CTX_free);
    assert(ctx && EVP_PKEY_keygen_init(ctx.get()) == 1);
    assert(EVP_PKEY_CTX_set_rsa_keygen_bits(ctx.get(), 2048) == 1);
    EVP_PKEY* raw = nullptr;
    assert(EVP_PKEY_keygen(ctx.get(), &raw) == 1);
    Owned<EVP_PKEY, EVP_PKEY_free> key(raw, EVP_PKEY_free);
    auto issuer = certificate(key.get(), 1);
    auto leaf = certificate(key.get(), 2);
    auto other = certificate(key.get(), 3);
    Owned<OCSP_CERTID, OCSP_CERTID_free> id(OCSP_cert_to_id(nullptr, leaf.get(), issuer.get()), OCSP_CERTID_free);
    Owned<OCSP_CERTID, OCSP_CERTID_free> wrong(OCSP_cert_to_id(nullptr, other.get(), issuer.get()), OCSP_CERTID_free);
    int count = 0;
    for (int wanted : {V_OCSP_CERTSTATUS_GOOD, V_OCSP_CERTSTATUS_REVOKED, V_OCSP_CERTSTATUS_UNKNOWN}) {
        auto bytes = responseFor(id.get(), wanted, issuer.get(), key.get());
        int result = -1;
        assert(ZParseOcspStatus(bytes.data(), bytes.size(), id.get(), result) && result == wanted); ++count;
        assert(!ZParseOcspStatus(bytes.data(), bytes.size(), wrong.get(), result)); ++count;
        for (std::size_t length = 0; length < bytes.size(); ++length) {
            assert(!ZParseOcspStatus(bytes.data(), length, id.get(), result)); ++count;
        }
        bytes.push_back(0);
        assert(!ZParseOcspStatus(bytes.data(), bytes.size(), id.get(), result)); ++count;
    }
    auto valid = responseFor(id.get(), V_OCSP_CERTSTATUS_GOOD, issuer.get(), key.get());
    int status = -1;
    assert(!ZParseOcspStatus(nullptr, 0, id.get(), status)); ++count;
    assert(!ZParseOcspStatus(valid.data(), valid.size(), nullptr, status)); ++count;
    assert(!ZParseOcspStatus(valid.data(), 1024 * 1024 + 1, id.get(), status)); ++count;
    for (int code : {OCSP_RESPONSE_STATUS_TRYLATER, OCSP_RESPONSE_STATUS_UNAUTHORIZED,
                     OCSP_RESPONSE_STATUS_MALFORMEDREQUEST, OCSP_RESPONSE_STATUS_SUCCESSFUL}) {
        Owned<OCSP_RESPONSE, OCSP_RESPONSE_free> response(OCSP_response_create(code, nullptr), OCSP_RESPONSE_free);
        auto bytes = encode(response.get());
        assert(!ZParseOcspStatus(bytes.data(), bytes.size(), id.get(), status)); ++count;
    }
    const unsigned char garbage[] = {0x30, 0x80, 0xff, 0x01, 0x00};
    assert(!ZParseOcspStatus(garbage, sizeof(garbage), id.get(), status)); ++count;
    for (int i = 0; i < 1000; ++i) {
        assert(ZParseOcspStatus(valid.data(), valid.size(), id.get(), status)); ++count;
    }
    std::printf("OCSP parser: %d checks passed, including malformed/truncated responses and repeated parsing\n", count);
}
