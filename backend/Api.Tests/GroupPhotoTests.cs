using System.Net;

namespace Kvitta.Api.Tests;

/// <summary>
/// The shared group picture: any member sets it, only members see it, and it can be taken back —
/// which is the property that keeps it out of the immutable log.
/// </summary>
[Collection(nameof(KvittaApiCollection))]
public sealed class GroupPhotoTests(KvittaApiFixture fixture)
{
    /// <summary>Smallest thing that passes the JPEG check: the SOI marker and some bytes.</summary>
    private static byte[] TinyJpeg(byte filler = 0x01) => [0xFF, 0xD8, 0xFF, filler, 0x00, 0x11];

    private Task<HttpResponseMessage> Put(Guid groupId, byte[] bytes, Guid asUser)
    {
        var request = new HttpRequestMessage(HttpMethod.Put, $"/api/v1/groups/{groupId}/photo")
        {
            Content = new ByteArrayContent(bytes)
        };
        request.Headers.Authorization = new("Bearer", TestTokens.AccessTokenFor(asUser));
        return fixture.Client.SendAsync(request);
    }

    private Task<HttpResponseMessage> Get(Guid groupId, Guid asUser, string? ifNoneMatch = null)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, $"/api/v1/groups/{groupId}/photo");
        request.Headers.Authorization = new("Bearer", TestTokens.AccessTokenFor(asUser));
        if (ifNoneMatch is not null)
        {
            request.Headers.TryAddWithoutValidation("If-None-Match", ifNoneMatch);
        }
        return fixture.Client.SendAsync(request);
    }

    private Task<HttpResponseMessage> Delete(Guid groupId, Guid asUser)
    {
        var request = new HttpRequestMessage(HttpMethod.Delete, $"/api/v1/groups/{groupId}/photo");
        request.Headers.Authorization = new("Bearer", TestTokens.AccessTokenFor(asUser));
        return fixture.Client.SendAsync(request);
    }

    [Fact]
    public async Task A_member_sets_the_photo_and_a_member_reads_it_back()
    {
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());

        var photo = TinyJpeg();
        var setting = await Put(owner.GroupId, photo, owner.UserId);
        Assert.Equal(HttpStatusCode.NoContent, setting.StatusCode);
        Assert.NotNull(setting.Headers.ETag);

        var reading = await Get(owner.GroupId, owner.UserId);
        Assert.Equal(HttpStatusCode.OK, reading.StatusCode);
        Assert.Equal("image/jpeg", reading.Content.Headers.ContentType?.MediaType);
        Assert.Equal(photo, await reading.Content.ReadAsByteArrayAsync());
        Assert.Equal(setting.Headers.ETag, reading.Headers.ETag);
    }

    [Fact]
    public async Task A_matching_etag_gets_304_and_no_body()
    {
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());
        var setting = await Put(owner.GroupId, TinyJpeg(), owner.UserId);

        var unchanged = await Get(owner.GroupId, owner.UserId, setting.Headers.ETag!.ToString());

        Assert.Equal(HttpStatusCode.NotModified, unchanged.StatusCode);
        Assert.Empty(await unchanged.Content.ReadAsByteArrayAsync());
    }

    [Fact]
    public async Task A_stranger_can_neither_set_nor_read()
    {
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());
        await Put(owner.GroupId, TinyJpeg(), owner.UserId);

        var stranger = await fixture.ScenarioAsync();

        Assert.Equal(HttpStatusCode.Forbidden, (await Put(owner.GroupId, TinyJpeg(0x02), stranger.UserId)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Get(owner.GroupId, stranger.UserId)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Delete(owner.GroupId, stranger.UserId)).StatusCode);
    }

    [Fact]
    public async Task Deleting_takes_the_photo_back()
    {
        // The property that justifies a mutable column over an event.
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());
        await Put(owner.GroupId, TinyJpeg(), owner.UserId);

        var clearing = await Delete(owner.GroupId, owner.UserId);
        Assert.Equal(HttpStatusCode.NoContent, clearing.StatusCode);

        Assert.Equal(HttpStatusCode.NotFound, (await Get(owner.GroupId, owner.UserId)).StatusCode);
    }

    [Fact]
    public async Task A_group_without_a_photo_is_404()
    {
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());

        Assert.Equal(HttpStatusCode.NotFound, (await Get(owner.GroupId, owner.UserId)).StatusCode);
    }

    [Fact]
    public async Task Bytes_that_are_not_jpeg_are_refused()
    {
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());

        var response = await Put(owner.GroupId, [0x89, 0x50, 0x4E, 0x47], owner.UserId);

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
    }

    [Fact]
    public async Task An_oversized_photo_is_refused()
    {
        var owner = await fixture.ScenarioAsync();
        await fixture.Client.PushAsync(owner, owner.OpeningBatch());

        var oversized = new byte[1024 * 1024 + 1];
        oversized[0] = 0xFF;
        oversized[1] = 0xD8;

        var response = await Put(owner.GroupId, oversized, owner.UserId);

        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
    }
}
