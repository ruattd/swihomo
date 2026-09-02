#include <stddef.h>
#include <stdint.h>

int SwihomoCoreStart(
    uint8_t *profile,
    size_t profileLength,
    const char *homeDirectory
);
int SwihomoCoreInputPacket(uint8_t *packet, size_t length, int family);
// Positive return values are HTTP status codes; values below 100 are bridge error codes.
int SwihomoCoreAPIRequest(
    const char *method,
    const char *target,
    uint8_t *body,
    size_t bodyLength,
    uint8_t **response,
    size_t *responseLength
);
void SwihomoCoreStop(void);
void SwihomoCoreFreeMemory(uint64_t *before, uint64_t *after);
char *SwihomoCoreLastError(void);
char *SwihomoCoreExternalResources(void);
char *SwihomoCoreProxyGroupOrder(void);
int SwihomoCoreReadExternalResource(const char *identifier, uint8_t **contents, size_t *length);
int SwihomoCoreWriteExternalResource(const char *identifier, uint8_t *contents, size_t length);
void SwihomoCoreFreeString(char *value);
void SwihomoCoreFreeData(uint8_t *value);
