// Linked list traversal: dependent loads (pointer chasing).
#define N 512
struct node { struct node *next; int val; };
static struct node nodes[N];

int main(void)
{
    // Link the nodes in a scrambled order.
    for (int i = 0; i < N; i++) {
        int j = (i * 37) % N, k = ((i + 1) * 37) % N;
        nodes[j].val = i;
        nodes[j].next = i + 1 < N ? &nodes[k] : 0;
    }
    int sum = 0;
    for (int rep = 0; rep < 8; rep++)
        for (struct node *p = &nodes[0]; p; p = p->next)
            sum += p->val;
    return sum == 8 * (N * (N - 1) / 2) ? 0 : 1;
}
